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

    /// New Reminder settings, persisted with working defaults (ADR 0012) so the
    /// capture is fully functional before any Settings UI exists (issue #37): ask
    /// for a due date, and either ask for the list or route to a default one.
    @AppStorage(ReminderSettings.askDateKey) private var reminderAskDate = true
    @AppStorage(ReminderSettings.askListKey) private var reminderAskList = true
    @AppStorage(ReminderSettings.defaultListIDKey) private var reminderDefaultListID = ""

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
    /// The brief, non-blocking confirmation toast (issue #37): a copy-out, or the
    /// tappable "Reminder added" that opens the reminder in the Reminders app.
    @State private var toast: Toast?
    @State private var toastToken = UUID()

    @State private var keyboardLayout = KeyboardLayoutModel()
    @State private var clipboard = ClipboardPrefillModel()

    /// The active quick capture (issue #37): when capturing, the breadcrumb owns
    /// the bottom input and the morphing control replaces the result list. Generic
    /// over the capture kind — New Reminder today — via the `Capture` recipe handed
    /// to `start`.
    @State private var capture = CaptureModel()

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
                // The New Reminder quick capture (issue #37). This indexed
                // instance is only for matching by name; activating it rebuilds a
                // configured Action from the user's reminder lists + settings.
                IndexedProvider(catalog: [.newReminder()]),
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

    /// How entering/leaving a capture moves (ADR 0010 budget): a deliberate spring
    /// when motion is allowed, a brief crossfade under Reduce Motion.
    private var captureMotion: MotionStyle {
        MotionPolicy(reduceMotion: reduceMotion).style(for: .captureTransition)
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
                    if capture.isCapturing {
                        // A capture in flight replaces the result list with its
                        // morphing control (the fuzzy choice list or date picker).
                        // It fades in while the browse list it replaces slides out
                        // the bottom, toward the keyboard (issue #37).
                        CaptureContent(model: capture)
                            .transition(.opacity)
                    } else if isHome {
                        HomeView(
                            content: engine.home(),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) }
                        )
                        .transition(captureMotion.edgeTransition(from: .bottom))
                    } else {
                        ResultListView(
                            results: engine.results(for: query),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) }
                        )
                        .transition(captureMotion.edgeTransition(from: .bottom))
                    }
                }

                if let toast {
                    ConfirmationToast(toast: toast) { openToast(toast) }
                }
            }
            // The capture breadcrumb rides the top with a progressive blur, the
            // content sliding under it (issue #37). Shown only at the root and only
            // while a session is collecting — the primer/denial affordances have no
            // steps and live solely in the bottom bar.
            .overlay(alignment: .top) {
                if path.isEmpty && capture.isCapturing {
                    CaptureBreadcrumbBar(model: capture)
                        .transition(captureMotion.edgeTransition(from: .top))
                }
            }
            // Glide the whole capture in and out as one gesture (issue #37): the
            // browse list slides out the bottom while the breadcrumb slides in from
            // the top, and the reverse on finishing or cancelling. Scoped to the
            // `isCapturing` flip so ordinary Home↔Results swaps stay instant; the
            // motion (and its Reduce-Motion crossfade) comes from the tested budget.
            .animation(captureMotion.animation, value: capture.isCapturing)
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
                    if capture.isActive {
                        // A capture (or its denial affordance) owns the bottom
                        // region: the breadcrumb + the morphing input replace the
                        // search field and paste chip (issue #37).
                        GlassEffectContainer(spacing: 8) {
                            CaptureBar(model: capture)
                        }
                    } else {
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
            }
            // The launcher itself wears no navigation bar — it is the root; the
            // management pages push *on top* of it, sliding in from the right with
            // the system edge-swipe back.
            .toolbar(.hidden, for: .navigationBar)
            // Clear the search query the moment a capture takes over the screen —
            // for the authorized path this coincides with the session starting, so
            // the browse list slides straight out into the capture rather than
            // blinking to an empty Home first; for the primer/denial affordances it
            // fires on the tap, clearing the stale results behind them. Returning
            // from a capture then lands on a clean Home (issue #37).
            .onChange(of: capture.isActive) { _, active in
                if active { query = "" }
            }
            // Flash the brief confirmation a completed capture reports (issue #37),
            // the same non-blocking acknowledgement as a copy-out.
            .onChange(of: capture.confirmation) { _, new in
                guard let new else { return }
                // A successful add carries a deep link: show a tappable, longer-
                // lived toast with a trailing open glyph; a failure is a plain,
                // brief acknowledgement.
                flashConfirmation(
                    new.message,
                    systemImage: new.openURL == nil ? nil : "arrow.up.right",
                    openURL: new.openURL
                )
            }
            // A tactile beat the moment a capture validates (issue #37), paired with
            // the confirmation toast: a success notification when the record lands,
            // an error buzz when the write failed. Driven by the same `confirmation`
            // value, whose fresh id makes back-to-back captures each register as a
            // distinct trigger.
            .sensoryFeedback(trigger: capture.confirmation) { _, confirmation in
                guard let confirmation else { return nil }
                return confirmation.isError ? .error : .success
            }
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

    /// Runs a row's main action. A multi-step capture (New Reminder) begins its
    /// breadcrumb instead of performing an outcome straight away; everything else
    /// performs its `ActionOutcome` at the platform edge. Selecting an Action
    /// records a frecency event (issue #9 AC #2).
    private func run(_ action: Action) {
        signals.record(action.id)
        if action.kind == .reminder {
            startReminderCapture()
            return
        }
        perform(action.run(input: query))
    }

    /// Begins the New Reminder capture (issue #37): hand off to the capture model,
    /// which resolves EventKit permission (primer → system dialog) just-in-time
    /// before the breadcrumb starts (ADR 0012).
    ///
    /// The search field deliberately keeps first responder — the keyboard stays
    /// put — so when the title step's field appears it takes focus seamlessly
    /// instead of the keyboard dropping and springing back. Removing the search
    /// field as the capture takes over resets `inputFocused` to false on its own,
    /// so the return-trip `onAppear` refocus still fires as a real false→true.
    ///
    /// The query is cleared once the capture becomes active (the `isActive`
    /// `onChange`), not here — clearing it synchronously while the authorized
    /// session is still resolving on the actor would flash an empty Home for a
    /// frame before the capture slides in.
    private func startReminderCapture() {
        capture.start(
            ReminderCapture(
                settings: ReminderSettings(
                    askDate: reminderAskDate,
                    askList: reminderAskList,
                    defaultListID: reminderDefaultListID
                )
            ),
            layout: keyboardLayout.layout
        )
    }

    /// Performs a single-step Action's outcome at the platform edge.
    private func perform(_ outcome: ActionOutcome) {
        switch outcome {
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
        case .createReminder:
            // Reminder creation flows through the capture model on the final
            // commit, never a direct `run(input:)`, so there is nothing to do here.
            break
        case .none:
            break
        }
    }

    /// Flashes a brief, non-blocking toast acknowledging a silent outcome. A toast
    /// carrying an `openURL` is tappable and lingers longer (so there is time to
    /// tap it), with `systemImage` trailing the text as the open affordance; a
    /// plain one fades after a beat.
    private func flashConfirmation(_ message: String, systemImage: String? = nil, openURL url: URL? = nil) {
        let new = Toast(message: message, systemImage: systemImage, openURL: url)
        toastToken = new.id
        withAnimation { toast = new }
        let lifetime: Duration = url == nil ? .seconds(1.6) : .seconds(4)
        Task {
            try? await Task.sleep(for: lifetime)
            guard toastToken == new.id else { return }
            withAnimation { toast = nil }
        }
    }

    /// Taps through a tappable toast to the reminder it points at, opening it in
    /// the Reminders app (issue #37), and dismisses the toast.
    private func openToast(_ toast: Toast) {
        guard let url = toast.openURL else { return }
        openURL(url)
        withAnimation { self.toast = nil }
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

/// A brief, non-blocking confirmation shown at the bottom (issue #37): a silent
/// acknowledgement that never steals focus. A copy-out is plain text; the
/// "Reminder added" toast carries a deep link in `openURL`, so it becomes
/// tappable and shows a trailing `systemImage` as the open affordance.
private struct Toast {
    let id = UUID()
    let message: String
    var systemImage: String?
    var openURL: URL?
}

/// Renders a `Toast` as a glass capsule. Only a tappable toast (one with an
/// `openURL`) intercepts touches; a plain one lets them fall through to the
/// launcher beneath, so an acknowledgement never blocks the next keystroke.
private struct ConfirmationToast: View {
    let toast: Toast
    var onTap: () -> Void

    private var isTappable: Bool { toast.openURL != nil }

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Text(toast.message)
                    .font(.callout.weight(.medium))
                if let image = toast.systemImage {
                    Image(systemName: image)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(isTappable ? .regular.interactive() : .regular, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { onTap() }
            // Only the tappable reminder toast grabs touches; a plain copy toast
            // stays transparent to taps so it never blocks the input beneath it.
            .allowsHitTesting(isTappable)
            .accessibilityIdentifier(isTappable ? "reminder-confirmation" : "copy-confirmation")
            .accessibilityAddTraits(isTappable ? .isButton : [])
            .padding(.bottom, 90)
        }
        .transition(.opacity)
    }
}
