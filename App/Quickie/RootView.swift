import SwiftUI
import SwiftData
import UIKit
import Combine
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

    /// New Event settings, persisted with working defaults (ADR 0012) and tuned from
    /// Settings → Actions → New Event (issue #38): ask which calendar each capture,
    /// and create silently (vs. opening the pre-filled system event editor). The
    /// `@AppStorage` defaults must match `EventSettingsView`'s so the first read
    /// before any write agrees.
    @AppStorage(EventSettings.askCalendarKey) private var eventAskCalendar = true
    @AppStorage(EventSettings.defaultCalendarIDKey) private var eventDefaultCalendarID = ""
    @AppStorage(EventSettings.editorKey) private var eventUseEditor = false

    /// The user's ranking signals — pinned Favorites and Frecency of past
    /// selections — persisted across launches (issue #9).
    @State private var signals = SignalsStore.launch()

    /// The user's Fallback list state — explicit order + disabled set (ADR 0013),
    /// persisted across launches.
    @State private var fallbacks = FallbacksStore.launch()

    /// The user's Indexed Folder grants (CONTEXT.md → Indexed Folder; issue #49) —
    /// security-scoped bookmarks in a device-local, non-synced store (ADR 0016).
    @State private var indexedFolders = IndexedFoldersStore.launch()

    /// The File Search snapshot (CONTEXT.md → File Search; ADR 0015): a plain
    /// in-memory filename index rebuilt from the granted folders on launch,
    /// foreground, and grant change, and served to every keystroke by the pure
    /// `FileSearchProvider` so the Core never rescans the filesystem.
    @State private var fileIndex = FileIndexModel()

    /// Drives the snapshot rebuild on foreground (CONTEXT.md → File Search): the
    /// grants (or the files inside them) may have changed while backgrounded.
    @Environment(\.scenePhase) private var scenePhase

    /// The user's imported Shortcut Actions — `{ name, acceptsInput }` populated
    /// solely by the Sync Shortcut import (issue #45; ADR 0007), persisted across
    /// launches.
    @State private var shortcuts = ShortcutsStore.launch()

    @State private var query = ""
    /// Whether the **Search Files context** is active (CONTEXT.md → Search Files
    /// context; ADR 0014): entered by selecting the "Search Files" command row, it
    /// scopes the input to the filename index alone — a `[Search Files] ▸ …`
    /// breadcrumb over an uncapped, full-height file list — until dismissed. A plain
    /// flag, not the Argument-collection machinery: it commits no value, it just
    /// maintains a live scoped filter (ADR 0014 forbids shoehorning it into capture).
    @State private var inFileSearch = false
    /// A file being previewed in QuickLook (issue #51): holds the live
    /// security-scoped access, released when the sheet dismisses.
    @State private var filePreview: FilePreviewRequest?
    /// A note opened for reading or a seeded compose editor — presented as a
    /// sheet, distinct from the pushed management pages.
    @State private var activeSheet: ActiveSheet?
    /// A pending **Share** secondary action (CONTEXT.md → Secondary action; ADR
    /// 0017): the resolved item(s) handed to the iOS share sheet, plus — for a file
    /// — the live security-scoped access held open until the sheet dismisses.
    @State private var shareRequest: ShareRequest?
    /// The navigation stack of pushed management pages (CONTEXT.md → Management
    /// page): each is *pushed* from the launcher so it slides in from the right
    /// and supports the system edge-swipe back, rather than rising as a sheet.
    @State private var path: [ManagementPage] = []
    @FocusState private var inputFocused: Bool
    /// The brief, non-blocking confirmation toast (issue #37): a copy-out, or the
    /// tappable "Reminder added" that opens the reminder in the Reminders app.
    @State private var toast: Toast?
    @State private var toastToken = UUID()
    /// The **held** keyboard height that lifts the bottom bar (issue #58). We drive
    /// the lift manually — SwiftUI's automatic keyboard avoidance is disabled on the
    /// launcher (`.ignoresSafeArea(.keyboard)`) — and only ever grow this to a real
    /// software-keyboard height, never resetting it when the keyboard hides. So when
    /// a row's long-press context menu resigns first responder and drops the keyboard
    /// (a system behaviour with no public override), the layout stays frozen instead
    /// of collapsing the safe area and jerking the reversed result list downward.
    @State private var lockedKeyboardInset: CGFloat = 0

    @State private var keyboardLayout = KeyboardLayoutModel()
    @State private var clipboard = ClipboardPrefillModel()

    /// The active quick capture (issue #37): when capturing, the breadcrumb owns
    /// the bottom input and the morphing control replaces the result list. Generic
    /// over the capture kind — New Reminder today — via the `Capture` recipe handed
    /// to `start`.
    @State private var capture = CaptureModel()

    /// The New Event editor-mode presenter (issue #38): editor mode hands the
    /// collected draft here, and its `request` drives the system event editor sheet.
    @State private var eventEditor = EventEditorPresenter()

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
        // Imported Shortcut Actions surface by name like Quicklinks/Snippets
        // (issue #45); inert this slice (triggering is the next). `acceptsInput`
        // rides along for that future trigger, changing nothing here.
        let storedShortcuts = shortcuts.entries.map { entry in
            Action.shortcut(name: entry.name, acceptsInput: entry.acceptsInput)
        }
        return SearchEngine(
            providers: [
                // The Dynamic Calculator + unit-conversion Provider.
                CalculatorProvider(),
                // File Search (CONTEXT.md → File Search; ADR 0015): a ranked-dynamic
                // Provider serving the current filename snapshot. Its survivors are
                // scored and ranked by match quality, never boosted to the top, so
                // an exact command name still outranks a strong filename hit.
                FileSearchProvider(index: fileIndex.index, layout: keyboardLayout.layout),
                // The built-in management command rows (Settings, Quicklinks,
                // Fallbacks) — no default links, no privileged web search.
                IndexedProvider.builtIns(),
                IndexedProvider(catalog: storedLinks),
                IndexedProvider(catalog: storedFallbackQueries),
                IndexedProvider(catalog: storedSnippets + [.newSnippet()]),
                IndexedProvider(catalog: storedNotes + [.newNote()]),
                // Imported Shortcut Actions, matched by name (issue #45).
                IndexedProvider(catalog: storedShortcuts),
                // The Notes / Snippets / Shortcuts library command rows.
                IndexedProvider(catalog: [.openNotesLibrary(), .openSnippetsLibrary(), .openShortcutsPage()]),
                // The New Reminder quick capture (issue #37). This indexed
                // instance is only for matching by name; activating it rebuilds a
                // configured Action from the user's reminder lists + settings.
                IndexedProvider(catalog: [.newReminder()]),
                // The New Event quick capture (issue #38). Like New Reminder, this
                // indexed instance is only for matching by name; activating it
                // rebuilds a configured Action from the user's calendars + settings.
                IndexedProvider(catalog: [.newEvent()]),
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

    /// The bottom safe-area (home-indicator) inset, read from the active window. The
    /// keyboard's reported overlap is measured from the screen bottom, but the bar
    /// already sits above the home indicator, so we subtract this to avoid lifting it
    /// one home-indicator's-worth too high.
    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
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
        // In the Search Files context the filename index alone answers each
        // keystroke — uncapped, and browsing everything before a filter is typed
        // (ADR 0014) — so its results and highlight come from the provider's
        // `contextMatches`, not the central engine.
        let fileResults = inFileSearch
            ? FileSearchProvider(index: fileIndex.index, layout: keyboardLayout.layout)
                .contextMatches(for: query)
            : []
        let highlighted = inFileSearch
            ? fileResults.first
            : (isHome ? nil : engine.highlighted(for: query))

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
                    } else if inFileSearch {
                        // The scoped file-browsing surface (ADR 0014): an uncapped,
                        // full-height list of filename matches under the breadcrumb.
                        FileSearchResultList(results: fileResults, onRun: run)
                            .transition(captureMotion.edgeTransition(from: .bottom))
                    } else if isHome {
                        HomeView(
                            content: engine.home(),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) },
                            onSecondaryAction: performSecondary
                        )
                        .transition(captureMotion.edgeTransition(from: .bottom))
                    } else {
                        ResultListView(
                            results: engine.results(for: query),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) },
                            onSecondaryAction: performSecondary
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
                } else if path.isEmpty && inFileSearch {
                    // The `[Search Files] ▸ …` breadcrumb, on the same blur band as a
                    // capture's, with a × that returns to normal results (ADR 0014).
                    FileSearchBreadcrumbBar(query: query, onDismiss: exitFileSearch)
                        .transition(captureMotion.edgeTransition(from: .top))
                }
            }
            // Slide the Search Files context in and out as one gesture, matching the
            // capture transition budget (ADR 0010).
            .animation(captureMotion.animation, value: inFileSearch)
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
                // Lift the bar by the *held* keyboard height rather than letting the
                // system track the live keyboard, so a transient dismissal (a
                // context menu) doesn't reflow the content. Only at the root — a
                // pushed page removes the bar, so it must reserve no phantom inset.
                Group {
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
                            // Bottom-align so the paste chip stays pinned to the
                            // input's bottom edge as the field grows upward (issue #63).
                            HStack(alignment: .bottom, spacing: 8) {
                                InputBar(
                                    query: $query,
                                    focused: $inputFocused,
                                    placeholder: inFileSearch ? "Search files…" : "Type to search…",
                                    returnKey: highlighted?.returnKeyLabel ?? ReturnKeyLabel.none,
                                    onSubmit: { if let highlighted { run(highlighted) } },
                                    glassNamespace: glassNamespace
                                )
                                // The clipboard paste chip belongs to Home, not the
                                // scoped file filter — hide it in the context.
                                if !inFileSearch && clipboardPrefill.isChipOffered {
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
                // Reserve the held keyboard height so the bar floats where the
                // keyboard's top is — and stays there when the keyboard drops. Zero
                // when a page is pushed (the bar is gone), so no phantom inset.
                .padding(.bottom, path.isEmpty ? lockedKeyboardInset : 0)
                .animation(.easeOut(duration: 0.25), value: lockedKeyboardInset)
            }
            // Drive the bar lift ourselves: turn off SwiftUI's automatic keyboard
            // avoidance for the launcher so the live keyboard never moves the layout
            // (the pushed pages set this on themselves; this covers the root + its
            // bottom inset). `lockedKeyboardInset` supplies the lift instead.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // Capture the software-keyboard height as it appears and **hold** it: on
            // hide the end frame reads off-screen (overlap 0), which the threshold
            // ignores, so the inset stays put across a context menu's transient
            // dismissal. Only a real keyboard (not a hardware-keyboard accessory bar)
            // clears the threshold.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let overlap = UIScreen.main.bounds.height - endFrame.minY
                guard overlap > 120 else { return }
                lockedKeyboardInset = max(0, overlap - bottomSafeAreaInset)
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
            // Inbound `quickie://` URLs are dispatched here at the app root by host
            // (issue #45, #46; ADR 0007). Two families ride the scheme: the Sync
            // Shortcut's `quickie://import?names=…`, which the store ingests (parse →
            // auto-prune reconcile → persist), and the run callbacks a triggered
            // Shortcut Action comes back on. An unrecognized URL is ignored.
            .onOpenURL { url in
                if shortcuts.handle(url: url) { return }
                handleShortcutResult(url)
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
            // Build the File Search snapshot on launch, then rebuild it whenever the
            // app returns to the foreground or the Indexed-Folder grants change
            // (CONTEXT.md → File Search; ADR 0015). Each rebuild walks the granted
            // folders under a per-folder security-scoped bracket, off the main actor.
            .task { fileIndex.rebuild(from: indexedFolders) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { fileIndex.rebuild(from: indexedFolders) }
            }
            .onChange(of: indexedFolders.grants) { _, _ in
                fileIndex.rebuild(from: indexedFolders)
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
            // New Event's editor mode (issue #38): the pre-filled system event editor
            // the user reviews instead of a silent write. Dismissing it (save, cancel,
            // or delete) re-arms the launcher's focus, like the compose sheets.
            .sheet(item: $eventEditor.request, onDismiss: { refocusInput() }) { request in
                EventEditorView(draft: request.draft) { eventEditor.request = nil }
                    .ignoresSafeArea()
            }
            // The QuickLook preview of an opened File Search result (issue #51). The
            // security-scoped access opened to resolve the file is released the moment
            // the preview closes, balancing the start/stop bracket (ADR 0015). Staying
            // a sheet keeps the Search Files context (or the result list) behind it, so
            // dismissing returns straight to browsing.
            .sheet(item: $filePreview, onDismiss: { refocusInput() }) { request in
                FilePreview(fileURL: request.access.fileURL)
                    .ignoresSafeArea()
                    // Release the security-scoped access when the preview goes away,
                    // balancing the start/stop bracket (ADR 0015). Read off the
                    // content's `onDisappear` — not the sheet's `onDismiss`, which
                    // fires after SwiftUI has already cleared the `item` binding.
                    .onDisappear { indexedFolders.endFileAccess(request.access) }
            }
            // The iOS share sheet for a **Share** secondary action (ADR 0017). A
            // file share holds the security-scoped access open while sharing and
            // releases it when the sheet goes away — the same start/stop bracket as
            // the QuickLook preview; a text/url/note share carries no access.
            .sheet(item: $shareRequest, onDismiss: { refocusInput() }) { request in
                ShareSheet(items: request.items)
                    .ignoresSafeArea()
                    .onDisappear {
                        if let access = request.fileAccess { indexedFolders.endFileAccess(access) }
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
        case .indexedFolders: IndexedFoldersView(store: indexedFolders)
        case .shortcuts: ShortcutsView(store: shortcuts)
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
        if action.kind == .event {
            startEventCapture()
            return
        }
        // An input-accepting Shortcut Action (its `acceptsInput` toggle on, so it
        // declares a `text` Argument) collects that input through the breadcrumb
        // before firing (issue #46); one with no Arguments fires immediately below.
        if action.kind == .shortcut && !action.arguments.isEmpty {
            startShortcutCapture(name: action.title)
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

    /// Begins the New Event capture (issue #38): hand off to the same capture model
    /// New Reminder uses, configured with an `EventCapture` recipe. The recipe
    /// resolves EventKit calendar permission (primer → system dialog) just-in-time
    /// before the breadcrumb starts (ADR 0012), and routes editor mode through the
    /// shared `eventEditor` presenter. The search field keeps first responder for the
    /// same seamless keyboard hand-off as the reminder capture.
    private func startEventCapture() {
        capture.start(
            EventCapture(
                settings: EventSettings(
                    askCalendar: eventAskCalendar,
                    defaultCalendarID: eventDefaultCalendarID,
                    useEditor: eventUseEditor
                ),
                presenter: eventEditor
            ),
            layout: keyboardLayout.layout
        )
    }

    /// Begins the input-collecting run of a Shortcut Action (issue #46): hand off to
    /// the same capture model, configured with a `ShortcutCapture` recipe. It needs
    /// no permission (running a shortcut is always available), so the breadcrumb
    /// starts straight away to collect the one optional `text` input, then fires the
    /// `shortcuts://x-callback-url/run-shortcut` open on commit.
    private func startShortcutCapture(name: String) {
        capture.start(ShortcutCapture(name: name), layout: keyboardLayout.layout)
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
        case .createReminder, .createEvent, .composeEvent:
            // Reminder and event creation (silent or editor handoff) flow through
            // the capture model on the final commit, never a direct `run(input:)`,
            // so there is nothing to do here.
            break
        case .openFile(let bookmarkID, let relativePath):
            // Resolve the file's Indexed-Folder bookmark + relative path to a
            // security-scoped URL and present it in QuickLook (CONTEXT.md → File
            // Search; ADR 0015). Access to the granting folder is opened here and
            // released when the preview dismisses. QuickLook carries its own Share /
            // open-in-place affordances, so no long-press secondary action is needed.
            if let access = indexedFolders.beginFileAccess(bookmarkID: bookmarkID, relativePath: relativePath) {
                filePreview = FilePreviewRequest(access: access)
            } else {
                flashConfirmation("File not found")
            }
        case .enterFileSearch:
            // Enter the scoped, uncapped Search Files context (ADR 0014): the input
            // now filters the filename index alone under the breadcrumb. Clear the
            // query so it opens browsing every file rather than filtered by the text
            // that surfaced the command.
            inFileSearch = true
            query = ""
        case .runShortcut(let name, let input):
            // Fire the shortcut by name via x-callback-url (CONTEXT.md → Shortcut
            // Action; issue #46), wiring the `quickie://` success/error/cancel
            // callbacks so the result comes back to `onOpenURL` below. This is the
            // no-input path (the toggle off); the input-collecting path runs through
            // the capture and opens the same URL from `ShortcutCapture`.
            openURL(ShortcutRun.runURL(name: name, input: input))
        case .none:
            break
        }
    }

    /// Performs a one-shot **secondary action** on a row's content (CONTEXT.md →
    /// Secondary action; ADR 0017). Core decides *which* verbs a row's content is
    /// eligible for; the App resolves the content **at the edge** and runs the verb
    /// — the same defer-to-the-edge pattern as the main-action outcomes. Only
    /// content-bearing rows reach here (a `.none` row offers no such menu item), so
    /// a resolution that comes back empty is a stale reference, not a dead item.
    private func performSecondary(_ action: Action, _ kind: SecondaryActionKind) {
        switch kind {
        case .copy:
            guard let text = copyableText(for: action) else {
                flashConfirmation("Nothing to copy")
                return
            }
            UIPasteboard.general.string = text
            flashConfirmation("Copied")
        case .share:
            presentShare(for: action)
        case .revealInFiles:
            revealInFiles(action)
        }
    }

    /// Resolves a row's content to the text a **Copy** puts on the pasteboard (ADR
    /// 0017): the snippet text / calculator number straight off its copy outcome,
    /// the URL string, a Note body fetched from the store by id, or a file's
    /// resolved path (under a security-scoped bracket). Returns `nil` only when a
    /// reference no longer resolves.
    private func copyableText(for action: Action) -> String? {
        switch action.content {
        case .text, .number:
            // Resolve against the current query so an input-consuming row (a
            // Fallback query) copies the URL it would actually open; self-contained
            // rows (Snippet, Calculator) ignore the input.
            if case .copyText(let text) = action.run(input: query) { return text }
            return nil
        case .url:
            if case .openURL(let url) = action.run(input: query) { return url.absoluteString }
            return nil
        case .noteBody(let id):
            return notes.first(where: { Self.noteActionID($0) == id })?.body
        case .file(let bookmarkID, let relativePath):
            guard let access = indexedFolders.beginFileAccess(bookmarkID: bookmarkID, relativePath: relativePath) else {
                return nil
            }
            defer { indexedFolders.endFileAccess(access) }
            return access.fileURL.path
        case .none:
            return nil
        }
    }

    /// Hands a row's content to the iOS **Share** sheet (ADR 0017): a URL is shared
    /// as a `URL` (so the sheet offers link actions), text/number/Note-body as a
    /// string, and a file as its resolved URL — holding the security-scoped access
    /// open until the sheet dismisses (`shareRequest.fileAccess`).
    private func presentShare(for action: Action) {
        switch action.content {
        case .text, .number:
            if case .copyText(let text) = action.run(input: query) { shareRequest = ShareRequest(items: [text]) }
        case .url:
            if case .openURL(let url) = action.run(input: query) { shareRequest = ShareRequest(items: [url]) }
        case .noteBody(let id):
            if let body = notes.first(where: { Self.noteActionID($0) == id })?.body {
                shareRequest = ShareRequest(items: [body])
            } else {
                flashConfirmation("Note not found")
            }
        case .file(let bookmarkID, let relativePath):
            if let access = indexedFolders.beginFileAccess(bookmarkID: bookmarkID, relativePath: relativePath) {
                shareRequest = ShareRequest(items: [access.fileURL], fileAccess: access)
            } else {
                flashConfirmation("File not found")
            }
        case .none:
            break
        }
    }

    /// **Reveal in Files** (ADR 0017): resolves the file's security-scoped bookmark
    /// and opens its location in the Files app via the `shareddocuments://` scheme.
    /// Only a `.file` row offers this verb, so anything else is a no-op.
    private func revealInFiles(_ action: Action) {
        guard case .file(let bookmarkID, let relativePath) = action.content,
              let access = indexedFolders.beginFileAccess(bookmarkID: bookmarkID, relativePath: relativePath) else {
            flashConfirmation("File not found")
            return
        }
        defer { indexedFolders.endFileAccess(access) }
        // Open the Files app at the file's location via the `shareddocuments://`
        // scheme. Percent-encode the path so spaces and other characters in a
        // filename don't break the URL and silently fail to open.
        let path = access.fileURL.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        if let url = URL(string: "shareddocuments://" + encoded) {
            openURL(url)
        } else {
            flashConfirmation("Can't reveal file")
        }
    }

    /// Leaves the Search Files context back to normal results (ADR 0014): the ×, or
    /// a future dismiss gesture. Clears the scoped filter so the launcher lands on a
    /// clean Home; the bottom input stayed mounted throughout, so focus persists.
    private func exitFileSearch() {
        inFileSearch = false
        query = ""
    }

    /// Handles a Shortcut Action run coming back over the `quickie://` scheme
    /// (CONTEXT.md → Shortcut Action; issue #46). `x-success` **reinjects** the
    /// returned output as the new query — the matcher re-runs and the Result list
    /// rebuilds as if the user had typed it — unconditionally: non-empty output gives
    /// the user something to act on, empty output clears the field to a fresh Home.
    /// `x-error` flashes a failure toast and leaves the query untouched; `x-cancel`
    /// is a silent no-op. A URL that isn't a run callback is ignored.
    private func handleShortcutResult(_ url: URL) {
        guard let result = ShortcutRun.result(from: url) else { return }
        switch result {
        case .reinject(let output):
            // Reinject onto the launcher root: drop any scoped file context so the
            // result rebuilds the normal Result list (or a clean Home when empty).
            inFileSearch = false
            query = output
        case .failed:
            flashConfirmation("Shortcut failed")
        case .cancelled:
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

/// A pending **Share** secondary action (CONTEXT.md → Secondary action; ADR 0017):
/// the resolved activity items handed to `UIActivityViewController`, plus a fresh
/// identity so each share drives a distinct `.sheet(item:)`. A file share also
/// carries the live `FileAccess`, held open while sharing and released when the
/// sheet dismisses; a text/url/note share leaves it `nil`.
private struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
    var fileAccess: FileAccess?
}

/// Presents the iOS share sheet (`UIActivityViewController`) for a **Share**
/// secondary action — the App edge that performs the verb Core only declared
/// eligible (ADR 0017).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
