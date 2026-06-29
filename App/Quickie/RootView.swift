import SwiftUI
import SwiftData
import UIKit
import QuickieCore

/// The whole screen, and the whole loop made visible: a bottom auto-focused
/// input, a reversed Result list above it, and tap-to-run. The empty-query state
/// shows Home — a 2×2 Favorites grid over the Recent list (ADR 0008 / issue #36).
///
/// Management surfaces (Settings, Quicklinks, Fallbacks, All Notes, All Snippets)
/// are no longer chrome: each is reached by typing to surface a command row and
/// presents **full-screen** (ADR 0013 / CONTEXT.md → Management page). The old
/// top-right gear button and combined manage sheet are gone.
struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    /// User static Quicklinks from the store feed the index alongside the
    /// built-in command rows (ADR 0006: index rebuilt from the source of truth).
    @Query(sort: \StoredQuicklink.createdAt) private var quicklinks: [StoredQuicklink]

    /// User Fallback queries — templated, query-consuming Fallback Actions (ADR
    /// 0013). Web search is just a default-seeded one of these.
    @Query(sort: \StoredFallbackQuery.createdAt) private var fallbackQueries: [StoredFallbackQuery]

    /// User Snippets feed the same index — copy-out Actions ranked beside every
    /// other capability (issue #6).
    @Query(sort: \StoredSnippet.createdAt) private var snippets: [StoredSnippet]

    /// User Notes feed the same index — read Actions whose main action opens the
    /// note (issue #7), ranked beside every other capability.
    @Query(sort: \StoredNote.createdAt) private var notes: [StoredNote]

    /// The app-wide appearance preference (CONTEXT.md → Settings): Light / Dark /
    /// System, applied to the whole app via `preferredColorScheme`.
    @AppStorage("appearance") private var appearanceRaw = Appearance.default.rawValue

    /// The user's ranking signals — pinned Favorites and Frecency of past
    /// selections — persisted across launches (issue #9).
    @State private var signals = SignalsStore.launch()

    /// The user's Fallback list state — explicit order + disabled set (ADR 0013),
    /// persisted across launches.
    @State private var fallbacks = FallbacksStore.launch()

    @State private var query = ""
    /// A note opened for reading or a seeded compose editor — presented as a
    /// sheet, distinct from the pushed management pages.
    @State private var activeSheet: ActiveSheet?
    /// The navigation stack of pushed management pages (CONTEXT.md → Management
    /// page): each is *pushed* from the launcher so it slides in from the right
    /// and supports the system edge-swipe back, rather than rising as a sheet.
    @State private var path: [ManagementPage] = []
    @FocusState private var inputFocused: Bool
    @State private var copyConfirmation: String?
    @State private var copyToken = UUID()

    @State private var keyboardLayout = KeyboardLayoutModel()
    @State private var clipboard = ClipboardPrefillModel()

    /// Honour the system Reduce Motion setting: it gates the paste button's morph
    /// so the glass snaps in/out instead of interpolating (ADR 0010 motion budget).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The namespace the bottom Liquid Glass surfaces share so the paste button can
    /// morph in and out of the input's capsule (see `InputBar`, `ClipboardPasteButton`).
    @Namespace private var glassNamespace

    private var engine: SearchEngine {
        let storedLinks: [Action] = quicklinks.compactMap { link in
            guard let url = URL(string: link.urlString) else { return nil }
            return Action.quicklink(
                id: link.id,
                title: link.title,
                aliases: link.alias.map { [$0] } ?? [],
                url: url
            )
        }
        let storedFallbackQueries: [Action] = fallbackQueries.compactMap { query in
            Action.fallbackQuery(
                id: query.id,
                title: query.title,
                aliases: query.alias.map { [$0] } ?? [],
                template: query.urlString
            )
        }
        let storedSnippets = snippets.map { snippet in
            Action.snippet(
                id: "snippet.\(snippet.id)",
                title: snippet.title,
                body: snippet.body
            )
        }
        let storedNotes = notes.map { note in
            Action.note(id: Self.noteActionID(note), title: note.title)
        }
        return SearchEngine(
            providers: [
                // The Dynamic Calculator + unit-conversion Provider.
                CalculatorProvider(),
                // The built-in management command rows (Settings, Quicklinks,
                // Fallbacks) — no default links, no privileged web search.
                IndexedProvider.builtIns(),
                IndexedProvider(catalog: storedLinks),
                IndexedProvider(catalog: storedFallbackQueries),
                IndexedProvider(catalog: storedSnippets + [.newSnippet()]),
                IndexedProvider(catalog: storedNotes + [.newNote()]),
                // The Notes / Snippets library command rows.
                IndexedProvider(catalog: [.openNotesLibrary(), .openSnippetsLibrary()]),
            ],
            layout: keyboardLayout.layout,
            favorites: signals.favorites,
            frecency: signals.frecency,
            fallbackOrder: fallbacks.resolvedOrder(for: fallbackQueries.map(\.id)),
            disabledFallbacks: fallbacks.disabled
        )
    }

    private static func noteActionID(_ note: StoredNote) -> String {
        "note.\(note.id)"
    }

    private var isHome: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var clipboardPrefill: ClipboardPrefill {
        ClipboardPrefill(
            clipboardHasText: clipboard.clipboardHasText,
            isHome: isHome,
            hasBeenUsed: clipboard.hasBeenUsed
        )
    }

    var body: some View {
        let engine = self.engine
        let highlighted = isHome ? nil : engine.highlighted(for: query)

        NavigationStack(path: $path) {
            ZStack {
                QuietBackdrop()

                Group {
                    if isHome {
                        HomeView(
                            content: engine.home(),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) }
                        )
                    } else {
                        ResultListView(
                            results: engine.results(for: query),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) }
                        )
                    }
                }

                if let copyConfirmation {
                    CopyConfirmationBanner(text: copyConfirmation)
                }
            }
            // The input floats in the bottom safe area, with the paste button to
            // its right. Kept *inside* the launcher's content so the reversed
            // result list reserves space for it — the best match sits just above
            // the input rather than behind it — and the keyboard lifts it.
            //
            // Both surfaces live in one `GlassEffectContainer` so they read as a
            // single Liquid Glass body: when the clipboard offer comes and goes the
            // button morphs *out of and back into* the input's capsule (paired by
            // their `glassEffectID`s in `glassNamespace`) rather than just popping.
            //
            // Shown only while the launcher is on top (`path.isEmpty`): a pushed
            // page removes it, and popping back *re-adds* it. That fresh
            // appearance is the whole trick — its `onAppear` focuses a newly
            // laid-out field, so the keyboard rises beneath it exactly as on
            // launch, instead of a stale async refocus on a retained field that
            // never took (and a mid-transition refocus that stranded it behind the
            // keyboard).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if path.isEmpty {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            InputBar(
                                query: $query,
                                focused: $inputFocused,
                                returnKey: highlighted?.returnKeyLabel ?? ReturnKeyLabel.none,
                                onSubmit: { if let highlighted { run(highlighted) } },
                                glassNamespace: glassNamespace
                            )
                            if clipboardPrefill.isChipOffered {
                                ClipboardPasteButton(glassNamespace: glassNamespace) { text in
                                    query = text
                                    clipboard.markUsed()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    // Morph the button in/out as the offer changes — degraded to a
                    // snap under Reduce Motion (ADR 0010 motion budget).
                    .animation(reduceMotion ? nil : .smooth, value: clipboardPrefill.isChipOffered)
                    // Auto-focus on launch (the zero-wall promise, ADR 0012).
                    // Return-from-a-page focus is re-armed off the popped page's
                    // `onDisappear` (see the navigationDestination below) — a real
                    // event at pop completion, not a guessed delay.
                    .onAppear { inputFocused = true }
                }
            }
            // The launcher itself wears no navigation bar — it is the root; the
            // management pages push *on top* of it, sliding in from the right with
            // the system edge-swipe back.
            .toolbar(.hidden, for: .navigationBar)
            // Re-arm focus off the popped page's `onDisappear` — it fires when the
            // pop animation completes, the moment the launcher is back and its
            // input (re-added the instant `path` emptied) is fully laid out and
            // ready to focus. An event at the exact right time, not a delay racing
            // the transition. Guard `path.isEmpty` so it fires only on a return to
            // the root, never on app backgrounding mid-page.
            .navigationDestination(for: ManagementPage.self) {
                destinationView(for: $0)
                    // The launcher's input is focused — the keyboard is up — at
                    // the instant a page is pushed, and removing the input (the
                    // `path.isEmpty` inset above) drops the keyboard *while* the
                    // page slides in. A `List`-based page (Fallbacks, Quicklinks,
                    // Notes, Snippets) reserves keyboard-avoidance inset at push
                    // time and then animates it away as the keyboard descends —
                    // the white band that slides down off-screen. Settings is a
                    // `Form` and never showed it. None of these pages hosts a text
                    // field directly (editing is in sheets), so ignoring the
                    // keyboard's bottom inset here is purely cosmetic: it stops the
                    // page from tracking the dismissing keyboard, killing the band.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .onDisappear { if path.isEmpty { refocusInput() } }
            }
            // Run the Quicklink / Fallback query data migration once on launch and
            // seed the default web-search Fallback query (ADR 0013).
            .task {
                QuickieStore.migrateToFallbackQueries(in: modelContext)
                // Prune any pinned Favorite whose Action no longer resolves (a
                // deleted Snippet/Quicklink, or a stale id from a build that
                // derived ids from the unstable `persistentModelID.hashValue`) so
                // an invisible pin can't silently occupy a Favorites slot. The
                // @Query catalogs are loaded by the time this launch task runs.
                signals.reconcileFavorites(against: engine.resolvableHomeIDs())
            }
            // A note opened for reading or a seeded compose editor stays a sheet —
            // a quick modal task, distinct from the pushed management pages.
            // Dismissing a sheet also drops the keyboard, so re-arm focus on
            // return. `onDismiss` is itself the event — it fires *after* the
            // dismiss animation finishes, so no delay is needed.
            .sheet(item: $activeSheet, onDismiss: { refocusInput() }) { sheet in
                switch sheet {
                case .readNote(let note):
                    NoteEditorView(note: note)
                case .composeNote(let seed):
                    NoteEditorView(seed: seed.text)
                case .composeSnippet(let seed):
                    SnippetEditorView(seed: seed.text)
                }
            }
        }
        .preferredColorScheme(Appearance(stored: appearanceRaw).colorScheme)
    }

    /// The pushed view for a management page (CONTEXT.md → Management page). Each
    /// relies on the launcher's `NavigationStack` for its bar and back affordance,
    /// so none wraps itself in another stack.
    @ViewBuilder
    private func destinationView(for page: ManagementPage) -> some View {
        switch page {
        case .settings: SettingsView()
        case .quicklinks: QuicklinksView()
        case .fallbacks: FallbacksView(store: fallbacks)
        case .notes: NoteManagerView()
        case .snippets: SnippetManagerView()
        }
    }

    /// Re-arms focus on the launcher input after a page or sheet closes and the
    /// keyboard has dropped — extending the zero-wall promise (ADR 0012) to the
    /// return trip. Called from real UI events (the popped page's `onDisappear`,
    /// the sheet's `onDismiss`), each firing once the close animation is done — so
    /// there is no delay to guess and no transition to race.
    ///
    /// Toggle off→on rather than just assigning `true`: a dismissed sheet can leave
    /// the `FocusState` reading `true` even though UIKit resigned first responder,
    /// and re-assigning `true` to an already-`true` state lifts nothing. The `on`
    /// is deferred one runloop tick (not a timed wait) so the `off` registers as a
    /// distinct change first.
    private func refocusInput() {
        guard path.isEmpty, activeSheet == nil else { return }
        inputFocused = false
        Task { @MainActor in
            guard path.isEmpty, activeSheet == nil else { return }
            inputFocused = true
        }
    }

    /// Runs a row's main action and performs its outcome at the platform edge.
    /// Selecting an Action records a frecency event (issue #9 AC #2).
    private func run(_ action: Action) {
        signals.record(action.id)
        switch action.run(input: query) {
        case .openURL(let url):
            openURL(url)
        case .copyText(let text):
            UIPasteboard.general.string = text
            flashConfirmation("Copied")
        case .openNote(let id):
            if let note = notes.first(where: { Self.noteActionID($0) == id }) {
                activeSheet = .readNote(note)
            } else {
                flashConfirmation("Note not found")
            }
        case .composeNote(let seed):
            activeSheet = .composeNote(ComposeSeed(text: seed))
            query = ""
        case .composeSnippet(let seed):
            activeSheet = .composeSnippet(ComposeSeed(text: seed))
            query = ""
        case .openPage(let destination):
            // Push the management page so it slides in from the right with
            // edge-swipe back, and clear the query so popping returns to a clean
            // launcher rather than a stale result list.
            path.append(destination)
            query = ""
        case .none:
            break
        }
    }

    private func flashConfirmation(_ message: String) {
        let token = UUID()
        copyToken = token
        withAnimation { copyConfirmation = message }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard copyToken == token else { return }
            withAnimation { copyConfirmation = nil }
        }
    }
}

/// A one-shot seed for a compose editor: the typed text plus a fresh identity so
/// each invocation drives a distinct `.sheet(item:)` presentation.
private struct ComposeSeed: Identifiable {
    let id = UUID()
    let text: String
}

/// The note-reader / seeded-compose sheet, as an Identifiable enum so one
/// `.sheet(item:)` can present any of them.
private enum ActiveSheet: Identifiable {
    case readNote(StoredNote)
    case composeNote(ComposeSeed)
    case composeSnippet(ComposeSeed)

    var id: String {
        switch self {
        case .readNote(let note): return "read-\(note.id)"
        case .composeNote(let seed): return "compose-note-\(seed.id)"
        case .composeSnippet(let seed): return "compose-snippet-\(seed.id)"
        }
    }
}

/// The quiet adaptive backdrop the Liquid Glass chrome floats over (ADR 0010).
private struct QuietBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// The lightweight "Copied" confirmation: a brief, non-blocking banner that
/// acknowledges a silent copy-out without stealing focus from the input.
private struct CopyConfirmationBanner: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 90)
                .accessibilityIdentifier("copy-confirmation")
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
