import SwiftUI
import SwiftData
import UIKit
import Combine
import QuickieCore
import QuickieStoreKit

/// The whole screen, and the whole loop made visible: a bottom auto-focused
/// input, a reversed Result list above it, and tap-to-run. The empty-query state
/// shows Home — a 2×2 Favorites grid over the Recent list (ADR 0008 / issue #36).
///
/// Management surfaces (Settings, Quicklinks, Fallbacks, the Pile, All Snippets)
/// are no longer chrome: each is reached by typing to surface a command row and
/// presents **full-screen** (ADR 0013 / CONTEXT.md → Management page). The old
/// top-right gear button and combined manage sheet are gone.
struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    /// User static Quicklinks from the store feed the index alongside the
    /// built-in command rows (ADR 0006: index rebuilt from the source of truth).
    @Query(sort: \StoredQuicklink.createdAt) private var quicklinks: [StoredQuicklink]

    /// The store's Quicklinks as of the last return to `.active` (ADR 0022):
    /// `@Query` observes only in-process saves, so a Quicklink the Share
    /// Extension wrote while the app was backgrounded never fires it. Each
    /// foreground re-fetches the catalog explicitly, and `engine` indexes any
    /// row `@Query` hasn't seen yet — merged by id, so once `@Query` catches
    /// up (on the next in-process save) the merge is a no-op.
    @State private var foregroundQuicklinks: [StoredQuicklink] = []

    /// User Custom Actions — templated, slot-filling Actions whose fallback-flagged
    /// rows consume the typed query (CONTEXT.md → Custom Action; ADR 0021). Web
    /// search is just a default-seeded one of these.
    @Query(sort: \StoredCustomAction.createdAt) private var customActions: [StoredCustomAction]

    /// User Snippets feed the same index — copy-out Actions ranked beside every
    /// other capability (issue #6).
    @Query(sort: \StoredSnippet.createdAt) private var snippets: [StoredSnippet]

    /// Saved Pile entries feed the same index (CONTEXT.md → Pile; ADR 0018) —
    /// fuzzy-matched over their body text, staged (and consumed) by their main
    /// action, ranked beside every other capability.
    @Query(sort: \StoredPileEntry.createdAt) private var pileEntries: [StoredPileEntry]

    /// The app-wide appearance preference (CONTEXT.md → Settings): Light / Dark /
    /// System, applied to the whole app via `preferredColorScheme`.
    @AppStorage("appearance") private var appearanceRaw = Appearance.default.rawValue

    /// The app-level Home-surface toggles (CONTEXT.md → Settings; issue #65),
    /// read where those surfaces are built: **Clipboard prefill** gates the paste
    /// chip's offer, **Show Recents** gates Home's Frecency "Recent" list. Both
    /// default to on; the `@AppStorage` defaults must match `SettingsView`'s so
    /// the first read before any write agrees.
    @AppStorage(AppSettings.clipboardPrefillKey, store: AppGroup.defaults)
    private var clipboardPrefillEnabled = true
    @AppStorage(AppSettings.showRecentsKey, store: AppGroup.defaults)
    private var showRecents = true

    /// New Reminder settings, persisted with working defaults (ADR 0012) so the
    /// capture is fully functional and now rendered from the declared schema (ADR
    /// 0020; issue #69): ask for a due date, and pick the target list — empty is the
    /// "Ask each time" sentinel the generic renderer stores for a dynamic choice. The
    /// keys are Core-owned (`SettingsKey`) so the schema and this reader never drift.
    @AppStorage(SettingsKey.reminderAskDate) private var reminderAskDate = true
    @AppStorage(SettingsKey.reminderList) private var reminderList = ""

    /// New Event settings, persisted with working defaults (ADR 0012) and rendered
    /// from the schema (ADR 0020; issue #69): the target-calendar dynamic choice
    /// (empty = "Ask each time") and create silently vs. opening the pre-filled system
    /// event editor. Same Core-owned keys the schema declares.
    @AppStorage(SettingsKey.eventCalendar) private var eventCalendar = ""
    @AppStorage(SettingsKey.eventEditor) private var eventUseEditor = false

    /// The Calculator unit-conversion toggle and File Search inline-result cap — the
    /// representative new schema options (ADR 0020; issue #69), read here so flipping
    /// one on its provider page rebuilds the engine with the new provider config.
    @AppStorage(SettingsKey.calculatorUnitConversion) private var calculatorUnitConversion = true
    @AppStorage(SettingsKey.fileSearchInlineCap) private var fileSearchInlineCap = 3

    /// The user's ranking signals — pinned Favorites and Frecency of past
    /// selections — persisted across launches (issue #9).
    @State private var signals = SignalsStore.launch()

    /// The user's Fallback list state — the single enabled list (issue #114),
    /// persisted across launches.
    @State private var fallbacks = FallbacksStore.launch()

    /// The fallback ids seen eligible at any point this session — the guard that lets
    /// the enabled list forget a *genuinely* lost id (a Shortcut's accepts-input turned
    /// off) without dropping one merely not-yet-loaded at launch (issue #114). Session
    /// state only; it need not persist.
    @State private var everEligibleFallbacks: Set<String> = []

    /// The kind-level Enabled switches (CONTEXT.md → Disabled; issue #67),
    /// persisted across launches: the engine is rebuilt from this on every
    /// keystroke, and each provider page's Enabled toggle writes into it.
    @State private var providerEnablement = ProviderEnablementStore.launch()

    /// The user's instance-level Disabled state (CONTEXT.md → Disabled; issue
    /// #68) — single actions reversibly hidden from results, Recents, and
    /// Favorites, persisted across launches. Fallbacks keep their own set in
    /// `fallbacks` above, and the kind switches live in `providerEnablement`.
    @State private var instanceEnablement = EnablementStore.launch()

    /// Feeds a `dynamic choice` its live options (ADR 0020; issue #69) — the EventKit
    /// calendars / reminder lists the New Event / New Reminder pickers show. Injected
    /// into the provider pages' environment so the schema-rendered pickers read the
    /// same live source the captures build their steps from.
    @State private var dynamicSettingOptions = DynamicSettingOptions()

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
    /// A seeded compose editor (New Snippet) — presented as a sheet, distinct
    /// from the pushed management pages.
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
    /// Whether a result/Recent list is mid-drag (issue #58 × #64): the signal that
    /// tells a keyboard dismissal apart. A dismissal *while* scrolling is the
    /// intentional swipe (#64) — let the bar drop; one while still is the context
    /// menu resigning first responder — hold the inset so nothing reflows.
    @State private var listScrolling = false

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

    /// The Quicklink catalog the engine indexes: the live `@Query` snapshot
    /// plus any foreground-fetched row it hasn't seen yet (a Share Extension
    /// write — ADR 0022). The `modelContext` guard drops rows deleted in-app
    /// since the fetch (the same invalidated-snapshot trap `livePileEntries`
    /// documents).
    private var indexedQuicklinks: [StoredQuicklink] {
        let known = Set(quicklinks.map(\.id))
        let unseen = foregroundQuicklinks.filter { $0.modelContext != nil && !known.contains($0.id) }
        return quicklinks + unseen
    }

    private var engine: SearchEngine {
        let storedLinks: [Action] = indexedQuicklinks.compactMap { link in
            guard let url = URL(string: link.urlString) else { return nil }
            return Action.quicklink(
                id: link.id,
                title: link.title,
                aliases: link.alias.map { [$0] } ?? [],
                url: url
            )
        }
        let storedCustomActions: [Action] = customActions.compactMap { custom in
            // Build from the row's full `definition` — it carries the per-argument
            // type specs, so the breadcrumb morphs its control per type (issue #96).
            // Reconstructing the definition by hand here silently dropped the specs,
            // leaving every step a plain text field.
            custom.definition.makeAction(id: custom.id)
        }
        let storedSnippets = snippets.map { snippet in
            Action.snippet(
                id: snippet.actionID,
                title: snippet.title,
                body: snippet.body
            )
        }
        let storedPileEntries = livePileEntries.map { entry in
            Action.pileEntry(id: entry.actionID, text: entry.text)
        }
        // Imported Shortcut Actions surface by name like Quicklinks/Snippets
        // (issue #45); inert this slice (triggering is the next). `acceptsInput`
        // rides along for that future trigger, changing nothing here.
        let storedShortcuts = shortcuts.entries.map { entry in
            Action.shortcut(name: entry.name, acceptsInput: entry.acceptsInput)
        }
        // Derive the fallback-eligible set from the Actions already built above, so
        // `makeAction` (which re-parses each URL template via regex) runs once per
        // engine build rather than again inside `eligibleFallbackIDs` (issue #114).
        let eligibleActions = eligibleFallbacks(
            customActionActions: storedCustomActions, shortcutActions: storedShortcuts
        )
        return SearchEngine(
            providers: [
                // The Dynamic Calculator + unit-conversion Provider. The
                // unit-conversion branch is gated by its schema toggle (ADR 0020;
                // issue #69): off keeps the Calculator to arithmetic only.
                CalculatorProvider(unitConversion: calculatorUnitConversion),
                // File Search (CONTEXT.md → File Search; ADR 0015): a ranked-dynamic
                // Provider serving the current filename snapshot. Its survivors are
                // scored and ranked by match quality, never boosted to the top, so
                // an exact command name still outranks a strong filename hit. A
                // disabled Indexed Folder's files are dropped up front (issue #68
                // follow-up) — hidden while the grant stays revocable on its page.
                FileSearchProvider(
                    index: fileIndex.index,
                    layout: keyboardLayout.layout,
                    inlineCap: resolvedInlineCap,
                    disabledFolders: indexedFolders.disabledFolderIDs
                ),
                // The built-in management command rows (Settings, Quicklinks,
                // Fallbacks) — no default links, no privileged web search. No
                // ProviderID: these are each provider's typed route back to its
                // page, so they must outlive any kind's disable (issue #67).
                IndexedProvider.builtIns(),
                // The user-content catalogs, each attributed to its configurable
                // kind (issue #67) so the Disabled state can key the kind's
                // Enabled toggle and each action's instance switch (issue #68)
                // against it.
                IndexedProvider(catalog: storedLinks, id: .quicklinks),
                // Custom Actions are their own configurable kind now (ADR 0021; issue
                // #94): the catalog attributes to `.customActions`, so the Custom
                // Actions page's Enabled toggle governs them all — eligible for the
                // Fallback list or not. The Fallbacks page activates the eligible ones
                // through `FallbacksStore`'s enabled list, an independent region axis.
                IndexedProvider(catalog: storedCustomActions, id: .customActions),
                IndexedProvider(catalog: storedSnippets + [.newSnippet()], id: .snippets),
                IndexedProvider(catalog: storedPileEntries + [.saveForLater()], id: .pile),
                // Imported Shortcut Actions, matched by name (issue #45).
                IndexedProvider(catalog: storedShortcuts, id: .shortcuts),
                // The Pile / Snippets / Shortcuts library command rows — kind-less
                // like the built-ins, so a disabled provider stays reachable.
                IndexedProvider(catalog: [.openPilePage(), .openSnippetsLibrary(), .openShortcutsPage()]),
                // The New Reminder quick capture (issue #37). This indexed
                // instance is only for matching by name; activating it rebuilds a
                // configured Action from the user's reminder lists + settings.
                IndexedProvider(catalog: [.newReminder()], id: .reminders),
                // The New Event quick capture (issue #38). Like New Reminder, this
                // indexed instance is only for matching by name; activating it
                // rebuilds a configured Action from the user's calendars + settings.
                IndexedProvider(catalog: [.newEvent()], id: .events),
            ],
            layout: keyboardLayout.layout,
            favorites: signals.favorites,
            frecency: signals.frecency,
            // The single enabled Fallback list (issue #114), reconciled against the
            // live fallback-eligible catalog so a deleted or now-ineligible action
            // drops out. Region membership is `Action.isFallbackEligible` ∧ presence
            // here; the disabled pool is derived, never stored.
            enabledFallbacks: fallbacks.resolvedEnabled(for: eligibleActions.map(\.id)),
            enablement: providerEnablement.enablement,
            disabledInstances: instanceEnablement.disabled
        )
    }

    /// The fallback-eligible subset of the catalog's Actions — text-first Custom
    /// Actions, accepts-input Shortcuts, and the two permanent built-in captures
    /// (CONTEXT.md → Fallback Action; issue #114), derived from shape with no stored
    /// flag. Takes the already-built Action arrays so the caller controls how many
    /// times `makeAction`/`shortcut` runs: the hot `engine` build passes its locals
    /// (one pass per keystroke); the cold computed property below rebuilds them.
    private func eligibleFallbacks(customActionActions: [Action], shortcutActions: [Action]) -> [Action] {
        (customActionActions + shortcutActions + [.saveForLater(), .newSnippet()])
            .filter(\.isFallbackEligible)
    }

    /// Every fallback-eligible Action in the live catalog — the Fallbacks page splits
    /// these into the enabled section and the derived pool, and `fallbackSeed` /
    /// `onChange` read them off the hot path. Rebuilds the Actions (cold: only on
    /// navigation, selection, or a catalog change), so it doesn't share the engine's
    /// per-keystroke locals.
    private var eligibleFallbackActions: [Action] {
        eligibleFallbacks(
            customActionActions: customActions.compactMap { $0.definition.makeAction(id: $0.id) },
            shortcutActions: shortcuts.entries.map { Action.shortcut(name: $0.name, acceptsInput: $0.acceptsInput) }
        )
    }

    /// The ids of `eligibleFallbackActions`, in a stable order — what the enabled
    /// list reconciles against and the page's pool is derived from.
    private var eligibleFallbackIDs: [String] { eligibleFallbackActions.map(\.id) }


    /// The Pile entries that are safe to read this instant. A just-consumed
    /// entry can linger in the `@Query` snapshot after its deletion commits,
    /// and once SwiftData frees the deleted row's snapshot — which can happen
    /// *seconds* later, not at save time — touching its backing data traps:
    /// the recurring CI crash behind issue #62's tap-to-stage, killing a later
    /// keystroke's engine rebuild. `modelContext == nil` is the one check that
    /// stays safe on an invalidated instance (`isDeleted` reads the backing
    /// data too, so guarding with it *was* the trap); every `pileEntries` read
    /// goes through this filter.
    private var livePileEntries: [StoredPileEntry] {
        pileEntries.filter { $0.modelContext != nil }
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

    /// The File Search inline cap, clamped through the declared stepper (ADR 0020;
    /// issue #69) so a stale or out-of-bounds store never drives the provider past
    /// its bounds — the same `clamped` the renderer reads through.
    private var resolvedInlineCap: Int {
        guard case .stepper(let stepper)? = ProviderID.fileSearch.settingsSchema
            .first(where: { $0.key == SettingsKey.fileSearchInlineCap })?.kind
        else { return fileSearchInlineCap }
        return stepper.clamped(fileSearchInlineCap)
    }

    private var clipboardPrefill: ClipboardPrefill {
        ClipboardPrefill(
            isEnabled: clipboardPrefillEnabled,
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
            ? FileSearchProvider(
                index: fileIndex.index,
                layout: keyboardLayout.layout,
                disabledFolders: indexedFolders.disabledFolderIDs
            ).contextMatches(for: query)
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
                            content: engine.home(showRecents: showRecents),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) },
                            onSecondaryAction: performSecondary,
                            onScrollActive: { listScrolling = $0 }
                        )
                        .transition(captureMotion.edgeTransition(from: .bottom))
                    } else {
                        ResultListView(
                            results: engine.results(for: query),
                            onRun: run,
                            isFavorite: { signals.isFavorite($0.id) },
                            canFavorite: { signals.canFavorite($0.id) },
                            onToggleFavorite: { signals.toggleFavorite($0.id) },
                            onSecondaryAction: performSecondary,
                            onScrollActive: { listScrolling = $0 }
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
                // Kill keyboard avoidance on the bar *itself*: the outer
                // `.ignoresSafeArea(.keyboard)` leaves a small residual lift on
                // `.safeAreaInset` content, which released on a context-menu dismiss
                // and dropped the list by ~half a row. Our held inset is the only
                // thing that should position the bar.
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            // Drive the bar lift ourselves: turn off SwiftUI's automatic keyboard
            // avoidance for the launcher so the live keyboard never moves the layout
            // (the pushed pages set this on themselves; this covers the root + its
            // bottom inset). `lockedKeyboardInset` supplies the lift instead.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // Reconcile the held inset with the ways the keyboard leaves:
            //  • **Showing** (a real keyboard, overlap over the threshold — not a
            //    hardware-keyboard accessory bar): lift the bar to sit on it.
            //  • **Hiding while the list is being dragged**: an intentional
            //    swipe-dismiss (issue #64) — release the inset so the bar drops and
            //    more results show.
            //  • **Hiding while a capture shows a keyboard-less control** (the date
            //    step's picker + commit button, the primer/denial affordances): the
            //    text field was *removed* for the whole step, so the keyboard is
            //    structurally gone — release the inset so the control takes the
            //    keyboard's space rather than floating above a dead band.
            //  • **Hiding while *not* scrolling** otherwise: the context menu
            //    resigned first responder — **hold** the inset so the long-press
            //    doesn't reflow the list. This is the whole point of driving the
            //    lift ourselves.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let overlap = UIScreen.main.bounds.height - endFrame.minY
                if overlap > 120 {
                    lockedKeyboardInset = max(0, overlap - bottomSafeAreaInset)
                } else if listScrolling || capture.usesKeyboardlessControl {
                    lockedKeyboardInset = 0
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
                    // the Pile, Snippets) reserves keyboard-avoidance inset at push
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
            // Seed the default web-search Custom Action once on launch (ADR 0021).
            .task {
                QuickieStore.seedDefaultCustomActions(in: modelContext)
                // Collapse same-id Custom Action duplicates to a deterministic
                // winner (ADR 0023): two devices can each seed the fixed-id web
                // search before their first CloudKit import lands, so launch
                // reconciles whatever sync merged in.
                QuickieStore.dedupeCustomActions(in: modelContext)
                // Collapse any stored notes from a pre-Pile build into titleless
                // Pile entries (ADR 0018).
                QuickieStore.migrateNotesToPile(in: modelContext)
                // Prune any pinned Favorite whose Action no longer resolves (a
                // deleted Snippet/Quicklink, or a stale id from a build that
                // derived ids from the unstable `persistentModelID.hashValue`) so
                // an invisible pin can't silently occupy a Favorites slot. The
                // @Query catalogs are loaded by the time this launch task runs.
                signals.reconcileFavorites(against: engine.resolvableHomeIDs())
                // One-time migration to the single enabled Fallback list (issue
                // #114): enabled = old order minus old disabled, with the pre-enabled
                // web-search + capture trio seeded for fresh installs. Independent of
                // the catalog's load timing so the seeded web search is pre-enabled
                // even before @Query surfaces it.
                fallbacks.migrateIfNeeded(
                    firstRunDefaults: FallbackActivation.firstRunEnabledIDs(webSearchID: QuickieStore.seedWebSearchID)
                )
                everEligibleFallbacks.formUnion(eligibleFallbackIDs)
                // Couple instance-disable with the Fallback list: a disabled action is
                // demoted out of the enabled list into the Available pool, so it never
                // renders as active and re-enabling doesn't restore its old rank.
                fallbacks.demoteDisabled(instanceEnablement.disabled)
            }
            // Keep that coupling live: disabling an action anywhere (its home page or
            // the Fallbacks page) demotes it from the enabled Fallback list.
            .onChange(of: instanceEnablement.disabled) { _, disabled in
                fallbacks.demoteDisabled(disabled)
            }
            // Forget an enabled fallback's rank when its eligibility is *genuinely*
            // lost (a Shortcut whose accepts-input was turned off, a Custom Action
            // retyped or deleted, a re-sync that dropped a shortcut) — regaining
            // eligibility re-enters it as a pool newcomer (issue #114). The
            // session-accumulated `everEligibleFallbacks` set is what tells a real
            // loss from a value not-yet-loaded at launch, so the pre-enabled default
            // is never mistaken for a loss and dropped. No-op before migration.
            .onChange(of: eligibleFallbackIDs) { _, ids in
                everEligibleFallbacks.formUnion(ids)
                fallbacks.pruneToEligible(liveEligible: ids, everEligible: everEligibleFallbacks)
            }
            // Re-run the dedup when the Custom Action catalog changes: the
            // remote-notification background mode lets a CloudKit import land a
            // duplicate seed *mid-session*, after the launch pass above already
            // ran — a launcher stays resident between cold starts, so waiting
            // for the next relaunch could leave two "Search the web" rows
            // visible for days. A duplicate always changes the row count, the
            // pass is idempotent and no-op-cheap, and deferring it out of the
            // view-update tick keeps the store mutation off the render pass.
            .onChange(of: customActions.count) { _, _ in
                Task { QuickieStore.dedupeCustomActions(in: modelContext) }
            }
            // Build the File Search snapshot on launch, then rebuild it whenever the
            // app returns to the foreground or the Indexed-Folder grants change
            // (CONTEXT.md → File Search; ADR 0015). Each rebuild walks the granted
            // folders under a per-folder security-scoped bracket, off the main actor.
            .task { fileIndex.rebuild(from: indexedFolders) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    fileIndex.rebuild(from: indexedFolders)
                    // Re-fetch the Quicklink catalog so anything the Share
                    // Extension saved while backgrounded appears in results
                    // (ADR 0022: foreground re-index, no cross-process signal).
                    // Write the @State only when the catalog actually changed:
                    // an unconditional write invalidates the whole root on
                    // every activation — including the launch transition,
                    // where that no-op invalidation raced the first render
                    // (issue #112's near-deterministic CI crash on this
                    // branch). A failed fetch keeps the previous catalog —
                    // resetting to empty would drop already-merged rows.
                    if let fetched = try? modelContext.fetch(
                        FetchDescriptor<StoredQuicklink>(sortBy: [SortDescriptor(\.createdAt)])
                    ), fetched.map(\.id) != foregroundQuicklinks.map(\.id) {
                        foregroundQuicklinks = fetched
                    }
                }
            }
            .onChange(of: indexedFolders.grants) { _, _ in
                fileIndex.rebuild(from: indexedFolders)
            }
            // A seeded compose editor stays a sheet — a quick modal task,
            // distinct from the pushed management pages. Dismissing a sheet
            // also drops the keyboard, so re-arm focus on return. `onDismiss`
            // is itself the event — it fires *after* the dismiss animation
            // finishes, so no delay is needed.
            .sheet(item: $activeSheet, onDismiss: { refocusInput() }) { sheet in
                switch sheet {
                case .composeSnippet(let seed):
                    SnippetEditorView(seed: seed.text)
                case .editSnippet(let snippet):
                    SnippetEditorView(snippet: snippet)
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
        // Every provider page's Options section reads and writes the same
        // kind-level Enabled switches the engine filters by (issue #67) — the
        // pages are pushed inside this stack, so root injection reaches them all.
        .environment(providerEnablement)
        // …and the live options a schema `dynamic choice` shows (ADR 0020; issue
        // #69), so the New Event / New Reminder pickers resolve their calendars /
        // lists wherever the page is reached.
        .environment(dynamicSettingOptions)
    }

    /// The pushed view for a management page (CONTEXT.md → Management page). Each
    /// relies on the launcher's `NavigationStack` for its bar and back affordance,
    /// so none wraps itself in another stack.
    @ViewBuilder
    private func destinationView(for page: ManagementPage) -> some View {
        switch page {
        case .settings(let panel):
            if let panel {
                providerPage(for: panel)
            } else {
                SettingsView()
            }
        case .pile:
            // The Pile *entries* page (ADR 0018): pure content to view and act
            // on — stage or discard, deliberately no per-entry disable (a
            // deferred query is acted on or kept in results, never "kept but
            // hidden") — distinct from the Pile provider's options-only
            // settings page, which the hub's Providers list reaches via
            // `.settings(panel: .pile)`.
            PileView(onStage: stage)
        }
    }

    /// A provider's unified Management page under the Settings hub (ADR 0019;
    /// issue #66) — the one destination both its typed Settings command row and
    /// the hub's Providers row resolve to. Content providers lead their existing
    /// list page with an Options section; the instance-less providers
    /// (Calculator, Reminders) show only Options; Events hosts the former New
    /// Event panel as its options; File Search hosts the folder grants — the
    /// former standalone Indexed Folders page, folded in as its content.
    @ViewBuilder
    private func providerPage(for provider: ProviderID) -> some View {
        switch provider {
        case .quicklinks: QuicklinksView(enablement: instanceEnablement)
        case .customActions: CustomActionsView(enablement: instanceEnablement)
        case .fallbacks: FallbacksView(store: fallbacks, enablement: instanceEnablement, eligible: eligibleFallbackActions)
        case .snippets: SnippetManagerView(enablement: instanceEnablement)
        case .shortcuts: ShortcutsView(store: shortcuts, enablement: instanceEnablement)
        case .fileSearch: IndexedFoldersView(store: indexedFolders)
        // The Pile's settings page stays options-only (ADR 0018): its entries
        // are temporary content whose verbs — stage and discard — live on the
        // `.pile` entries page, the carve-out from the unified
        // content-under-options shape. Entries have no per-entry disable. Events
        // is now options-only too (issue #69): its former bespoke EventSettingsView
        // folded into the declared schema, so it renders like the others.
        case .pile, .reminders, .calculator, .events: ProviderOptionsPage(provider: provider)
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
        // Selected from the bottom fallback region it seeds-and-commits the typed
        // query as that input, so it runs in one tap (CONTEXT.md → Fallback Action;
        // issue #114); verb-first it opens the breadcrumb empty.
        if action.kind == .shortcut && !action.arguments.isEmpty {
            startShortcutCapture(name: action.title, seed: fallbackSeed(for: action))
            return
        }
        // A Custom Action always runs through the breadcrumb (CONTEXT.md → Custom
        // Action; ADR 0021): a fallback selection seeds-and-commits the typed query
        // as Argument 1 (a one-slot fallback finishes in one tap, a multi-slot one
        // continues at step 2), while verb-first (a name match) opens the breadcrumb
        // empty at Argument 1.
        if action.kind == .customAction {
            startCustomActionCapture(action)
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
        // The `-uitest-stub-reminders` seam: the same breadcrumb driven end-to-end
        // with only the EventKit edge stubbed, because XCUITest cannot pre-grant
        // the Reminders permission dialog (see `UITestReminderCapture`).
        if UITestReminderCapture.isRequested {
            capture.start(UITestReminderCapture(), layout: keyboardLayout.layout)
            return
        }
        capture.start(
            ReminderCapture(
                settings: ReminderSettings(
                    askDate: reminderAskDate,
                    listStored: reminderList
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
                    calendarStored: eventCalendar,
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
    private func startShortcutCapture(name: String, seed: String? = nil) {
        capture.start(ShortcutCapture(name: name), layout: keyboardLayout.layout, seed: seed)
    }

    /// Begins the breadcrumb run of a Custom Action (CONTEXT.md → Custom Action; ADR
    /// 0021). A fallback selection seeds-and-commits the typed query as Argument 1
    /// (`seed`), so a one-slot fallback like web search completes in one tap and a
    /// multi-slot one continues at step 2 with the seeded first pill sealed; a
    /// verb-first (name-matched) selection passes no seed, opening the breadcrumb
    /// empty. Opening a URL needs no permission, so the session starts straight away.
    private func startCustomActionCapture(_ action: Action) {
        capture.start(
            CustomActionCapture(action: action),
            layout: keyboardLayout.layout,
            seed: fallbackSeed(for: action)
        )
    }

    /// The query to **seed-and-commit** as Argument 1 when a fallback row is selected
    /// from the bottom region (CONTEXT.md → Fallback Action; issue #114) — else `nil`,
    /// opening the breadcrumb empty. Seeds only when the action is an *enabled*
    /// fallback (so a pooled, verb-first selection opens empty — an enabled fallback is
    /// deduped out of name matches, so any selection of it is a region selection) and
    /// something was actually typed (a pinned Favorite tapped on Home has an empty
    /// query, and seeding it would instantly fire a one-slot fallback with a blank
    /// value instead of asking for one).
    private func fallbackSeed(for action: Action) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              action.isFallbackEligible,
              fallbacks.resolvedEnabled(for: eligibleFallbackIDs).contains(action.id)
        else { return nil }
        return query
    }

    /// Performs a single-step Action's outcome at the platform edge.
    private func perform(_ outcome: ActionOutcome) {
        switch outcome {
        case .openURL(let url):
            openURL(url)
        case .copyText(let text):
            UIPasteboard.general.string = text
            flashConfirmation("Copied")
        case .copyAndStage(let text):
            // A math result's main action (CONTEXT.md → main action): copy the
            // answer *and* stage it back into the input so the user keeps
            // calculating from it. The clipboard write mirrors `copyText`; setting
            // `query` re-runs the matcher, the same reinjection as staging a Pile
            // entry — but on a literal value with nothing to consume. We are always
            // on the launcher root here (a calculator row only appears in Results),
            // so there is no page to pop.
            UIPasteboard.general.string = text
            query = text
            flashConfirmation("Copied")
        case .saveToPile(let text):
            // The silent "Save for later" capture (CONTEXT.md → Pile; ADR 0018):
            // drop the typed text straight into the Pile — no editor, no confirm,
            // no app switch — clear to Home, and acknowledge like a copy-out.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                modelContext.insert(StoredPileEntry(text: trimmed))
                flashConfirmation("Saved for later")
            }
            query = ""
        case .stagePileEntry(let id):
            if let entry = livePileEntries.first(where: { $0.actionID == id }) {
                stage(entry)
            } else {
                flashConfirmation("Not in the Pile")
            }
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
        case .edit:
            // Edit resolves per content: a Shortcut deeplinks into the Shortcuts
            // app's editor by name, a Snippet opens its stored record in-app.
            switch action.content {
            case .shortcut(let name):
                editShortcut(name)
            default:
                editSnippet(action)
            }
        }
    }

    /// **Edit** a Shortcut (ADR 0017): deeplinks into the Shortcuts app's editor for
    /// the shortcut by name via `shortcuts://open-shortcut` (CONTEXT.md → Shortcut
    /// Action). Only the name is needed — the same handle the run path carries — so
    /// unlike a Snippet there is no stored record to resolve; the App just opens the
    /// URL at the edge, the same defer-to-the-edge pattern as running one.
    private func editShortcut(_ name: String) {
        openURL(ShortcutRun.editURL(name: name))
    }

    /// **Edit** a Snippet (ADR 0017): resolves the row's `.snippet(id:)` content to
    /// its stored record and opens the Snippet editor on it — the same sheet the
    /// Snippets library uses for edits, reached here straight from a result's
    /// long-press. Only a `.snippet` row offers this verb; a stale id (the Snippet
    /// was deleted) acknowledges rather than opening an empty editor.
    private func editSnippet(_ action: Action) {
        guard case .snippet(let id) = action.content,
              let snippet = snippets.first(where: { $0.actionID == id }) else {
            flashConfirmation("Snippet not found")
            return
        }
        activeSheet = .editSnippet(snippet)
    }

    /// Resolves a row's content to the text a **Copy** puts on the pasteboard (ADR
    /// 0017): the snippet text / calculator number straight off its copy outcome,
    /// the URL string, a Pile entry's text fetched from the store by id, or a
    /// file's resolved path (under a security-scoped bracket). Returns `nil` only
    /// when a reference no longer resolves.
    private func copyableText(for action: Action) -> String? {
        switch action.content {
        case .text, .number, .snippet:
            // Resolve against the current query so an input-consuming row (a
            // Fallback query) copies the URL it would actually open; self-contained
            // rows (Snippet, Calculator) ignore the input. A Calculator's main
            // action copies *and* stages, so its text rides `copyAndStage`.
            switch action.run(input: query) {
            case .copyText(let text), .copyAndStage(let text): return text
            default: return nil
            }
        case .url:
            if case .openURL(let url) = action.run(input: query) { return url.absoluteString }
            return nil
        case .pileEntry(let id):
            return livePileEntries.first(where: { $0.actionID == id })?.text
        case .file(let bookmarkID, let relativePath):
            guard let access = indexedFolders.beginFileAccess(bookmarkID: bookmarkID, relativePath: relativePath) else {
                return nil
            }
            defer { indexedFolders.endFileAccess(access) }
            return access.fileURL.path
        case .none, .shortcut:
            // Neither carries copyable text — a command/capture row has no content,
            // and a Shortcut is a launchable reference whose only verb is Edit.
            return nil
        }
    }

    /// Hands a row's content to the iOS **Share** sheet (ADR 0017): a URL is shared
    /// as a `URL` (so the sheet offers link actions), text/number/Pile-entry text
    /// as a string, and a file as its resolved URL — holding the security-scoped
    /// access open until the sheet dismisses (`shareRequest.fileAccess`).
    private func presentShare(for action: Action) {
        switch action.content {
        case .text, .number, .snippet:
            switch action.run(input: query) {
            case .copyText(let text), .copyAndStage(let text): shareRequest = ShareRequest(items: [text])
            default: break
            }
        case .url:
            if case .openURL(let url) = action.run(input: query) { shareRequest = ShareRequest(items: [url]) }
        case .pileEntry(let id):
            if let text = livePileEntries.first(where: { $0.actionID == id })?.text {
                shareRequest = ShareRequest(items: [text])
            } else {
                flashConfirmation("Not in the Pile")
            }
        case .file(let bookmarkID, let relativePath):
            if let access = indexedFolders.beginFileAccess(bookmarkID: bookmarkID, relativePath: relativePath) {
                shareRequest = ShareRequest(items: [access.fileURL], fileAccess: access)
            } else {
                flashConfirmation("File not found")
            }
        case .none, .shortcut:
            // Nothing to share — a content-less command row, or a Shortcut whose
            // only verb is Edit (a launchable reference, not a value).
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

    /// Stages a Pile entry (CONTEXT.md → Stage), from either of its surfaces —
    /// its result row or its Pile-page row: replace the input query with the
    /// saved text (the matcher re-runs off the query change, the same
    /// reinjection move as a Shortcut result) and remove the entry from the
    /// Pile — staging consumes it. Clearing `path` pops the Pile page when
    /// staging starts there (a no-op from a result row, where the launcher is
    /// already on top), and the popped page's `onDisappear` re-arms focus, so
    /// either way the user lands "typing" the deferred query.
    private func stage(_ entry: StoredPileEntry) {
        let text = entry.text
        modelContext.delete(entry)
        // Commit the consume synchronously: leaving it to autosave opens a
        // window where the `@Query` snapshot still lists the entry after its
        // backing data is gone, and the next keystroke's engine rebuild traps
        // reading it (the CI crash on tap-to-stage). Saving here makes the
        // query republish without the entry in the same beat.
        try? modelContext.save()
        query = text
        path = []
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
/// sheet dismisses; a text/url/Pile share leaves it `nil`.
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

/// The Snippet editor sheets, as an Identifiable enum so the one `.sheet(item:)`
/// presentation point stays in place as sheets come and go: `composeSnippet`
/// seeds a brand-new Snippet from typed text (New Snippet), `editSnippet` opens
/// an existing one for revision (the **Edit** secondary action — ADR 0017).
private enum ActiveSheet: Identifiable {
    case composeSnippet(ComposeSeed)
    case editSnippet(StoredSnippet)

    var id: String {
        switch self {
        case .composeSnippet(let seed): return "compose-snippet-\(seed.id)"
        case .editSnippet(let snippet): return "edit-snippet-\(snippet.id)"
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
