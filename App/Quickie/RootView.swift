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
    /// sheet, distinct from the full-screen management pages.
    @State private var activeSheet: ActiveSheet?
    /// The full-screen management page currently presented, if any.
    @State private var activePage: PagePresentation?
    @FocusState private var inputFocused: Bool
    @State private var copyConfirmation: String?
    @State private var copyToken = UUID()

    @State private var keyboardLayout = KeyboardLayoutModel()
    @State private var clipboard = ClipboardPrefillModel()

    private var engine: SearchEngine {
        let storedLinks: [Action] = quicklinks.compactMap { link in
            guard let url = URL(string: link.urlString) else { return nil }
            return Action.quicklink(
                id: link.persistentModelID.hashValue.description,
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
                id: "snippet.\(snippet.persistentModelID.hashValue.description)",
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if clipboardPrefill.isChipOffered {
                    ClipboardPasteChip { text in
                        query = text
                        clipboard.markUsed()
                    }
                }
                InputBar(
                    query: $query,
                    focused: $inputFocused,
                    returnKey: highlighted?.returnKeyLabel ?? ReturnKeyLabel.none,
                    onSubmit: { if let highlighted { run(highlighted) } }
                )
            }
        }
        // Run the Quicklink / Fallback query data migration once on launch and
        // seed the default web-search Fallback query (ADR 0013), then auto-focus.
        .task {
            QuickieStore.migrateToFallbackQueries(in: modelContext)
        }
        .onAppear { inputFocused = true }
        .preferredColorScheme(Appearance(stored: appearanceRaw).colorScheme)
        // A note opened for reading or a seeded compose editor.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .readNote(let note):
                NoteEditorView(note: note)
            case .composeNote(let seed):
                NoteEditorView(seed: seed.text)
            case .composeSnippet(let seed):
                SnippetEditorView(seed: seed.text)
            }
        }
        // The management pages — each full-screen with its own dismiss.
        .fullScreenCover(item: $activePage) { presentation in
            switch presentation.page {
            case .settings: SettingsView()
            case .quicklinks: QuicklinksView()
            case .fallbacks: FallbacksView(store: fallbacks)
            case .notes: NoteManagerView()
            case .snippets: SnippetManagerView()
            }
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
        case .openPage(let page):
            // Opening a management page clears the query back to Home behind the
            // full-screen cover, so dismissing returns to a clean launcher.
            activePage = PagePresentation(page: page)
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

/// Wraps a `ManagementPage` so one `.fullScreenCover(item:)` can present any of
/// the five management pages.
private struct PagePresentation: Identifiable {
    let page: ManagementPage
    var id: String { "\(page)" }
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
