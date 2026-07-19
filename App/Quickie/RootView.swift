import SwiftUI
import SwiftData
import UIKit
import Combine
import WidgetKit
import QuickieCore
import QuickieStoreKit

/// The whole screen, and the whole loop made visible: a bottom auto-focused
/// input, a reversed Result list above it, and tap-to-run. The empty-query state
/// shows Home — a 2×2 Favorites grid over the Recent list (ADR 0008 / issue #36).
///
/// Management surfaces (Settings, Custom Actions, Fallbacks, the Pile, All Snippets)
/// are no longer chrome: each is reached by typing to surface a command row and
/// presents **full-screen** (ADR 0013 / CONTEXT.md → Management page). The old
/// top-right gear button and combined manage sheet are gone.
struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    /// User Custom Actions — URL Actions with zero or more `{name}` slots (CONTEXT.md
    /// → Custom Action; ADR 0021, 0030): a slotted one the breadcrumb fills, a slot-less
    /// one a static link that opens directly (the former Quicklink, now folded in). Web
    /// search is just a default-seeded one of these. They feed the index alongside the
    /// built-in command rows (ADR 0006: index rebuilt from the source of truth).
    @Query(sort: \StoredCustomAction.createdAt) private var customActions: [StoredCustomAction]

    /// The store's Custom Actions as of the last return to `.active` (ADR 0022):
    /// `@Query` observes only in-process saves, so a static link the Share Extension
    /// wrote while the app was backgrounded never fires it. Each foreground re-fetches
    /// the catalog explicitly, and `engine` indexes any row `@Query` hasn't seen yet —
    /// merged by id, so once `@Query` catches up (on the next in-process save) the
    /// merge is a no-op.
    @State private var foregroundCustomActions: [StoredCustomAction] = []

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

    /// New Reminder's **default-list** target (issue #145 follow-up), used when the
    /// List step is off: empty (or the system-default sentinel) is the system default
    /// list, any other value a fixed list id. Whether the list is *collected* is the
    /// reorderable step plan's business (`reminderSteps`), not this. Core-owned key.
    @AppStorage(SettingsKey.reminderList) private var reminderList = ""

    /// New Event's **default-calendar** target (issue #145 follow-up), used when the
    /// Calendar step is off, plus the silent-vs-editor toggle. The step plan
    /// (`eventSteps`) decides which steps are collected. Core-owned keys.
    @AppStorage(SettingsKey.eventCalendar) private var eventCalendar = ""
    @AppStorage(SettingsKey.eventEditor) private var eventUseEditor = false

    /// The Computed provider's five per-type toggles (ADR 0020, 0032) and the File
    /// Search inline-result cap, read here so flipping one on its provider page
    /// rebuilds the engine with the new provider config. Math and Unit conversion
    /// gate the Calculator rows; URLs, Phone numbers, and Email addresses gate the
    /// Detected result rows — all default-on.
    @AppStorage(SettingsKey.calculatorMath) private var calculatorMath = true
    @AppStorage(SettingsKey.calculatorUnitConversion) private var calculatorUnitConversion = true
    @AppStorage(SettingsKey.calculatorURL) private var calculatorURL = true
    @AppStorage(SettingsKey.calculatorPhone) private var calculatorPhone = true
    @AppStorage(SettingsKey.calculatorEmail) private var calculatorEmail = true
    @AppStorage(SettingsKey.fileSearchInlineCap) private var fileSearchInlineCap = 3

    /// The Pile's **Pending query** auto-save toggle (CONTEXT.md → Pending query;
    /// issue #152; ADR 0031), declared in the Pile provider's schema. On, text left
    /// unresolved in the root input when the app backgrounds is snapshotted and —
    /// depending on how and when the user returns — restored or committed to the
    /// Pile. Off is the old behavior exactly: state preserved indefinitely, entry
    /// surfaces discard, no Live Activity.
    @AppStorage(SettingsKey.pileAutoSave) private var pileAutoSave = true

    /// The user's ranking signals — pinned Favorites and Frecency of past
    /// selections — persisted across launches (issue #9).
    @State private var signals = SignalsStore.launch()

    /// The user's Fallback list state — the single enabled list (issue #114),
    /// persisted across launches.
    @State private var fallbacks = FallbacksStore.launch()

    /// The New Reminder / New Event **step plans** (issue #145 follow-up) — each the
    /// enabled, ordered steps the reorderable double-list on the provider page sets,
    /// seeded/migrated from the retired per-setting toggles. Read when a capture starts
    /// to build its breadcrumb; persisted across launches.
    @State private var reminderSteps = CaptureStepsStore.reminder()
    @State private var eventSteps = CaptureStepsStore.event()

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

    /// One-shot latch for the `-uitest-deeplink` seam so the seeded deeplink
    /// dispatches exactly once, even though `onAppear` can fire more than once.
    @State private var didDispatchLaunchDeeplink = false

    /// The measured height of the capture breadcrumb bar (a top overlay with no
    /// layout footprint), fed to `CaptureContent` so the choice list insets its
    /// scroll content and no option hides behind the breadcrumb (issue #37).
    @State private var captureBreadcrumbHeight: CGFloat = 0

    /// Whether the `-uitest-entry` seam is armed (issue #124). When set, the
    /// launcher carries a hidden trigger that fires the real `handleDeeplink(.entry)`
    /// — the deep-link widget's warm-resume reset — because XCUITest can neither
    /// deliver a `quickie://` URL nor tap a Home-Screen widget. Gated on
    /// `--uitesting` so the trigger can never surface in production.
    private var isUITestEntryArmed: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("-uitest-entry")
    }

    /// The foreground headline App Shortcuts' hand-off (issue #121; ADR 0024). A
    /// Quick Capture / New Reminder / New Event intent deposits its `quickie://` URL
    /// here after foregrounding the app, and this view drains it through the *same*
    /// `QuickieDeeplink.parse → handleDeeplink` the root `onOpenURL` runs — no second
    /// inbound path. Held as the shared instance so both the intent and this view
    /// see one inbox.
    @State private var deeplinkInbox = DeeplinkInbox.shared

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

    /// The Custom Action catalog the engine indexes: the live `@Query` snapshot plus
    /// any foreground-fetched row it hasn't seen yet (a Share Extension write — ADR
    /// 0022). The `modelContext` guard drops rows deleted in-app since the fetch (the
    /// same invalidated-snapshot trap `livePileEntries` documents).
    private var indexedCustomActions: [StoredCustomAction] {
        let known = Set(customActions.map(\.id))
        let unseen = foregroundCustomActions.filter { $0.modelContext != nil && !known.contains($0.id) }
        return customActions + unseen
    }

    private var engine: SearchEngine {
        let storedCustomActions: [Action] = indexedCustomActions.compactMap { custom in
            // Build from the row's full `definition` — it carries the per-argument
            // type specs, so the breadcrumb morphs its control per type (issue #96),
            // and a slot-less row factories a static (link) Action (ADR 0030).
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
        // Each entry wears its age in the muted subtitle channel (CONTEXT.md →
        // Pile, aging paragraph; issue #164) — the same relative-age label the
        // Pile page shows, formatted off the persisted creation date as of one
        // captured `now` so every row reads consistently within a build.
        let now = Date()
        let storedPileEntries = livePileEntries.map { entry in
            Action.pileEntry(
                id: entry.actionID,
                text: entry.text,
                age: RelativeAge.label(from: entry.createdAt, asOf: now)
            )
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
                // The Computed provider (ADR 0032): the Calculator (math + unit
                // conversion) plus Detected result rows (URL / phone / email). Each
                // of its five schema toggles suppresses exactly its rows; the three
                // detection toggles off restore the pre-detection Calculator.
                ComputedProvider(
                    math: calculatorMath,
                    unitConversion: calculatorUnitConversion,
                    url: calculatorURL,
                    phone: calculatorPhone,
                    email: calculatorEmail
                ),
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
                // The built-in management command rows (Settings, Custom Actions,
                // Fallbacks) — no privileged web search. No ProviderID: these are each
                // provider's typed route back to its page, so they must outlive any
                // kind's disable (issue #67).
                IndexedProvider.builtIns(),
                // Custom Actions are their own configurable kind (ADR 0021, 0030; issue
                // #94) — both slotted actions and static (slot-less) links, unified here.
                // The catalog attributes to `.customActions`, so the Custom Actions
                // page's Enabled toggle governs them all — eligible for the Fallback list
                // or not. The Fallbacks page activates the eligible ones through
                // `FallbacksStore`'s enabled list, an independent region axis.
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
                // The System umbrella's own built-in (CONTEXT.md → System
                // provider; ADR 0029): Open iOS Settings, attributed to `.system`
                // so the umbrella's Enabled toggle cascades over it (and, via
                // `isEffectivelyEnabled`, over the Reminders/Events catalogs above).
                // App Store Search is a default-seeded Custom Action instead (issue
                // #144), so it rides the Custom Actions catalog, not here.
                IndexedProvider(catalog: [.openIOSSettings()], id: .system),
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
        (customActionActions + shortcutActions
            + [.saveForLater(), .newSnippet(), .newReminder(), .newEvent()])
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

    /// The Live Activity's preview, or `nil` when no activity should be live
    /// (CONTEXT.md → Pending query; issue #152): the same Core qualification
    /// the background snapshot uses — a plain, non-empty root query with the
    /// auto-save toggle on — so the activity and the snapshot can never
    /// disagree on what counts as pending. The activity tracks the *input*:
    /// it starts on the first qualifying keystroke (already live when the
    /// user backgrounds, no request-at-background lag) and ends the moment
    /// the query empties, a main action resolves it, or a scoped context
    /// takes over.
    private var pendingActivityPreview: String? {
        PendingQuery.snapshot(
            query: query,
            isCapturing: capture.isActive,
            inFileSearch: inFileSearch,
            autoSaveEnabled: pileAutoSave
        )?.text
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

    /// Applies a `KeyboardBarLift` decision to the held inset. A notified change
    /// rides the keyboard's own motion: UIKit animates the keyboard with a stock
    /// spring (mass 3, stiffness 1000, damping 500 — the curve behind every
    /// keyboard show/hide since iOS 9), so animating our inset with the same
    /// spring keeps the bar glued to the keyboard's top edge instead of easing in
    /// after it has settled. A tracked change is a live drag sample — applied with
    /// animation off, because the finger is the animation. Instant under UI test,
    /// like all motion (issue #79).
    private func apply(_ change: KeyboardBarLift.Change) {
        switch change {
        case .animateWithKeyboard(let inset):
            withAnimation(
                MotionStyle.isInstantForUITesting
                    ? nil
                    : .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)
            ) {
                lockedKeyboardInset = inset
            }
        case .track(let inset):
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                lockedKeyboardInset = inset
            }
        case .hold:
            break
        }
    }

    /// How entering/leaving a capture moves (ADR 0010 budget): a deliberate spring
    /// when motion is allowed, a brief crossfade under Reduce Motion.
    private var captureMotion: MotionStyle {
        MotionPolicy(reduceMotion: reduceMotion).style(for: .captureTransition)
    }

    /// The [[Living backdrop]]'s drift period (seconds), or `nil` for a still mesh
    /// (ADR 0034). The *timing* lives in Core's `MotionPolicy`; this only decides
    /// the four cases that force a still backdrop, in the order they matter:
    ///
    /// - **Reduce Motion** collapses the moment to a `.fade` in Core, so `guard
    ///   case .drift` alone stills the mesh — no App-side motion flag needed.
    /// - **Anything but the bare Home landing**: `isHome` alone is not enough,
    ///   because a capture clears the query (`query = ""`, see the
    ///   `capture.isActive` handler below) and an empty-query file-search context
    ///   is also `isHome` — so the mesh would resume drifting *behind* those
    ///   surfaces. The drift runs only on the true landing (the same
    ///   `isHome && !capture.isActive && !inFileSearch` the pending-query auto-save
    ///   uses), keeping results read over a still backdrop through typing, results,
    ///   and capture (ADR 0010's type→choose→run protection).
    /// - **Low Power Mode**: ADR 0034 spends no battery on motion a seconds-long
    ///   session would never see through anyway.
    /// - **UI test**: the frozen-under-test behavior CI's XCUITest job gates
    ///   (issue #79), shared with every other motion via `isInstantForUITesting`.
    ///
    /// Returns the period when the mesh should move, or `nil` for a still backdrop
    /// — one value, so nothing downstream can hold "should drift" and "how fast"
    /// out of step.
    private var backdropDriftPeriod: Double? {
        let style = MotionPolicy(reduceMotion: reduceMotion).style(for: .backdropDrift)
        guard case .drift(let period) = style,
              isHome,
              !capture.isActive,
              !inFileSearch,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              !MotionStyle.isInstantForUITesting
        else { return nil }
        return period
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
                // The glow rides the bar, on the bar's own held inset — zero on a
                // pushed page, mirroring the bar's lift (issue #181 gives pages their
                // own backdrop).
                //
                // This is the bar's inset *exactly*, not the keyboard's overlap of the
                // screen bottom: the two differ by the bottom safe area, and reading
                // that (`bottomSafeAreaInset`, a `UIApplication` walk) from `body`
                // silently broke the result list — SwiftUI dropped the update that
                // renders the rows, so typing produced nothing, with no crash and no
                // slowdown to point at. Never read UIKit view state from `body`. The
                // omitted term is 34pt against a 140pt falloff, which is why the glow
                // still lands on the bar: it centers on the bar's safe-area line
                // rather than its top edge, a difference nothing can see.
                LivingBackdrop(
                    glowLift: path.isEmpty ? lockedKeyboardInset : 0,
                    driftPeriod: backdropDriftPeriod
                )

                Group {
                    if capture.isCapturing {
                        // A capture in flight replaces the result list with its
                        // morphing control (the fuzzy choice list or date picker).
                        // It fades in while the browse list it replaces slides out
                        // the bottom, toward the keyboard (issue #37).
                        CaptureContent(model: capture, topInset: captureBreadcrumbHeight)
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
                            onToggleFavorite: toggleFavorite,
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
                            onToggleFavorite: toggleFavorite,
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
                        // Measure the bar's height (a top overlay with no layout
                        // footprint) so the choice list can inset its scroll content
                        // and no option hides behind the breadcrumb (issue #37).
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captureBreadcrumbHeight = $0 }
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
                                        // The hand-off decision (QuickieCore): `hasStrings` metadata
                                        // can offer the chip over an empty/expired clipboard, so the
                                        // tapped content decides. A real paste seeds and retires the
                                        // offer; a dud withdraws the chip without burning it, so a
                                        // later real copy can re-offer.
                                        if let seeded = ClipboardPrefill.seededQuery(fromPasted: text) {
                                            query = seeded
                                            clipboard.markUsed()
                                        } else {
                                            clipboard.noteEmptyPaste()
                                        }
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
                apply(KeyboardBarLift.notified(
                    overlap: UIScreen.main.bounds.height - endFrame.minY,
                    bottomSafeArea: bottomSafeAreaInset,
                    isListScrolling: listScrolling,
                    usesKeyboardlessControl: capture.usesKeyboardlessControl
                ))
            }
            // The live channel: per-frame keyboard positions during an interactive
            // swipe-dismiss, so the bar follows the finger instead of waiting for
            // the commit notification. `dragged` drops every sample taken while
            // the list is still, so ordinary show/hide (and the held context-menu
            // inset) stay owned by the notified channel above.
            .background {
                KeyboardFrameObserver { overlap in
                    apply(KeyboardBarLift.dragged(
                        overlap: overlap,
                        bottomSafeArea: bottomSafeAreaInset,
                        isListScrolling: listScrolling
                    ))
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
            // A completed capture **resolves the query** like any main action
            // (CONTEXT.md → Main action): clear the input back to a clean Home and — via
            // `pendingActivityPreview` going nil — end the Pending query Live Activity.
            // The `isActive` clear above covers a capture that stays open (its query
            // becomes the breadcrumb), but a one-slot fallback Custom Action (web search)
            // completes inside `beginSession`, flipping `isActive` true→false with no net
            // change, so it needs this separate completion signal to clear.
            .onChange(of: capture.completions) { _, _ in query = "" }
            // Flash the brief confirmation a completed capture reports (issue #37),
            // the same non-blocking acknowledgement as a copy-out.
            .onChange(of: capture.confirmation) { _, new in
                guard let new else { return }
                // A tactile beat the moment a capture validates (issue #37), paired
                // with the confirmation toast: the success/error notification the
                // feedback budget declares (ADR 0034), fired through the same
                // `Haptics` call site as every other moment so the policy stays the
                // single source of truth (issue #180) rather than a second
                // `.sensoryFeedback` mapping the outcome itself.
                Haptics.play(new.isError ? .captureFailed : .captureSucceeded)
                // A successful add carries a deep link: show a tappable, longer-
                // lived toast with a trailing open glyph; a failure is a plain,
                // brief acknowledgement.
                flashConfirmation(
                    new.message,
                    systemImage: new.openURL == nil ? nil : "arrow.up.right",
                    openURL: new.openURL
                )
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
            // The `-uitest-entry` seam (issue #124): the deep-link widget opens
            // `quickie://entry` to reset a warm app to a clean, focused Home, but
            // XCUITest can neither deliver a `quickie://` URL nor tap a Home-Screen
            // widget, so the warm reset is otherwise undrivable. Under the flag the
            // launcher carries a hidden corner button that builds the widget's own
            // `quickie://entry` URL and drives it through the *real*
            // `QuickieDeeplink.parse → handleDeeplink` path — exactly what the
            // widget's `widgetURL` reaches through the root `onOpenURL` — so a test
            // can build state (a stale query, a half-filled breadcrumb) and prove the
            // tap clears it. Unlike the launch-time `-uitest-deeplink`/pin seams the
            // trigger must fire on demand, *after* the test has established state a
            // cold launch can't. Topmost overlay so it stays hittable; only the widget
            // UI test ever renders it (it is gated on `-uitest-entry`).
            .overlay(alignment: .topLeading) {
                if isUITestEntryArmed {
                    Button {
                        if let deeplink = QuickieDeeplink.parse(QuickieDeeplink.entryURL()) {
                            handleDeeplink(deeplink)
                        }
                    } label: {
                        // A *filled* swatch, not `Color.clear`: UIKit's hit-testing
                        // ignores any view with `alpha < 0.01`, so a truly invisible
                        // trigger silently swallows the tap (the bug that failed the
                        // first CI run). 0.06 is above that cutoff yet visually inert,
                        // and a solid rectangle gives XCUITest a real 44×44 target.
                        Color.primary.opacity(0.06)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("uitest-entry-trigger")
                }
            }
            // Inbound `quickie://` URLs are dispatched here at the app root by host
            // (issue #45, #46, #120; ADR 0007, 0024). Families ride the scheme: the
            // Sync Shortcut's `quickie://import?names=…`, which the store ingests
            // (parse → auto-prune reconcile → persist); the run callbacks a triggered
            // Shortcut Action comes back on; and the App Intents bridge / entry-surface
            // deeplink door (run / entry). Each parser claims only its own hosts, so
            // order is immaterial and an unrecognized URL falls through untouched.
            .onOpenURL { url in
                if let importedNames = shortcuts.handle(url: url) {
                    // Freshly imported Shortcut Actions start instance-disabled
                    // (CONTEXT.md → Shortcut Action): an import must never flood
                    // results — the user enables the ones they want from the
                    // Shortcuts page. Re-sync survivors keep their existing state.
                    instanceEnablement.disable(importedNames.map { Action.shortcutID(for: $0) })
                    return
                }
                if let deeplink = QuickieDeeplink.parse(url) { handleDeeplink(deeplink); return }
                handleShortcutResult(url)
            }
            // A foreground headline App Shortcut (issue #121; ADR 0024) deposits its
            // `quickie://` URL in the shared inbox after foregrounding the app; drain
            // it through the same parse → dispatch path. `onChange` catches a warm hit
            // (deposited after this view is on screen); the launcher's `onAppear` below
            // catches a cold hit (deposited before it existed). Draining consumes the
            // URL, so a relaunch never replays a stale route.
            .onChange(of: deeplinkInbox.pending) { _, _ in dispatchPendingDeeplink() }
            // The `-uitest-deeplink` seam: XCUITest can't deliver a `quickie://` URL,
            // so a UI test seeds one as a launch argument and the app dispatches it
            // through the *real* parse → `handleDeeplink` path once the launcher is on
            // screen — the same "drive the real path" approach the shortcut import and
            // Favorites pin tests use. A `capture/*` deeplink swaps the search field for
            // the capture breadcrumb, whose `capture-input` self-focuses
            // (`BackspaceTextField.becomeFirstResponder`), so it needs no prior search
            // focus. Gated on `--uitesting`, latched to fire once.
            .onAppear {
                dispatchUITestDeeplinkIfRequested()
                // Drain a cold-launch deposit: a foreground App Shortcut that launched
                // the app deposited its URL before this view existed, so `onChange`
                // never saw it.
                dispatchPendingDeeplink()
            }
            // Seed the default web-search Custom Action once on launch (ADR 0021).
            .task {
                // Resolve a cold launch's Pending query (issue #152; ADR 0031):
                // restore a < 30s text into the input, commit an expired one to
                // the Pile — the path that makes the snapshot survive
                // termination. The scenePhase observer covers warm foregrounds;
                // on a cold start its first value can already be `.active`, so
                // this is the reliable once-at-launch pass (`take` consumes the
                // snapshot, so both firing costs nothing). An entry-surface
                // launch's deeplink dispatch (`onAppear`, which runs first)
                // consumes it as a commit instead.
                resolvePendingQuery(via: .plainOpen)
                // Reconcile a leftover activity from a killed process with the
                // resolved input: a restored query adopts and keeps it, a
                // committed or absent one ends it.
                PendingQueryActivityController.sync(preview: pendingActivityPreview)
                // Convert any pre-0030 Quicklink rows to slot-less Custom Actions
                // before seeding, so an already-seeded `seed.link.*` link is present
                // and not double-inserted (ADR 0030).
                QuickieStore.migrateQuicklinksToCustomActions(in: modelContext)
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
                // an invisible pin can't silently occupy a Favorites slot.
                //
                // The default seed is now inserted in `QuickieApp.init` (before the
                // `@Query` first reads), so `resolvableHomeIDs()` normally already
                // sees it here. As defence-in-depth against any `@Query` refresh lag,
                // also fold the store's *actual* Custom Action ids in from a direct
                // fetch, so a pin to a freshly-seeded default (`seed.web-search`) can
                // never be pruned before its Home card draws. Only ids genuinely in
                // the store are added, so a pin to a deleted seed still prunes (no
                // ghost revival).
                let storedCustomActionIDs = (try? modelContext.fetch(
                    FetchDescriptor<StoredCustomAction>()
                ))?.map(\.id) ?? []
                signals.reconcileFavorites(
                    against: engine.resolvableHomeIDs().union(storedCustomActionIDs)
                )
                // One-time migration to the single enabled Fallback list (issue
                // #114): enabled = old order minus old disabled, with the pre-enabled
                // web-search + capture trio seeded for fresh installs. Independent of
                // the catalog's load timing so the seeded web search is pre-enabled
                // even before @Query surfaces it.
                fallbacks.migrateIfNeeded(
                    firstRunDefaults: FallbackActivation.firstRunEnabledIDs()
                )
                everEligibleFallbacks.formUnion(eligibleFallbackIDs)
                // Couple instance-disable with the Fallback list: a disabled action is
                // demoted out of the enabled list into the Available pool, so it never
                // renders as active and re-enabling doesn't restore its old rank.
                fallbacks.demoteDisabled(instanceEnablement.disabled)
                // Publish the initial Bridged Action snapshot (issue #122): `onChange`
                // only fires on later changes, so the out-of-process entity query needs
                // the set seeded here — after favorites are reconciled — so Siri and
                // Spotlight have the live members from the first launch onward.
                syncBridgedActions(engine.bridgedActions())
                // Publish the initial Favorites widget snapshot (ADR 0025; issue
                // #126) for the same reason: the widget renders from the App Group
                // projection alone, so it needs the reconciled grid from first
                // launch onward, not only after the next pin.
                publishWidgetFavorites(widgetFavoritesProjection)
                // Publish the initial eligible-action catalog (ADR 0027; #140) for
                // the same reason: the Actions widget picker and both render surfaces
                // read the App Group snapshot alone, so it needs the live eligible set
                // from first launch onward, not only after the next change.
                publishEligibleCatalog(eligibleCatalogProjection)
                // Drain the widget's frecency outbox for the cold-launch case: the
                // scenePhase observer below covers later foregrounds, but a run
                // performed while the app was fully terminated must be credited on
                // this first pass too (ADR 0025).
                drainWidgetRuns()
            }
            // Keep the Live Activity mirroring the unresolved input (issue #152):
            // the first qualifying keystroke starts it, each further one updates
            // its preview, and emptying or resolving the query — a main action,
            // a capture taking over, the Search Files context — ends it.
            .onChange(of: pendingActivityPreview) { _, preview in
                PendingQueryActivityController.sync(preview: preview)
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
            // Keep the **outward projections** in step — the Bridged Action set
            // (CONTEXT.md → Bridged Action; ADR 0024; issue #122), the Favorites
            // widget snapshot (ADR 0025; issue #126), and the eligible-action catalog
            // (ADR 0027; #140). Deriving them from the live `engine` catches *every*
            // way any of them can change through one signal — a pin/unpin, a
            // create/edit/delete (a rename shifts a title with no count change; a
            // Quicklink URL edit shifts a hand-off payload), a kind or instance
            // disable. One `onChange` observes all three rather than one each because
            // `body`'s modifier chain sits near the type-checker's budget — a second
            // observation of the same shape pushed RootView past "unable to type-check
            // in reasonable time" on CI. The closure only fires on a real change (the
            // value is `Equatable`), and each sync writes + nudges only when its
            // snapshot actually moved, so this stays off the keystroke hot path.
            .onChange(of: outwardProjections) { _, projections in
                syncBridgedActions(projections.bridged)
                publishWidgetFavorites(projections.widgetFavorites)
                publishEligibleCatalog(projections.catalog)
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
                if phase == .background {
                    // Snapshot the Pending query (CONTEXT.md → Pending query; ADR
                    // 0031): `(text?, timestamp)` to the App Group defaults, decided
                    // at the next activation by comparing timestamps — no background
                    // timer, and termination loses nothing. Text rides along only
                    // for a plain root query; a breadcrumb or the Search Files
                    // context still resets after the window but saves nothing. The
                    // Live Activity shares the same qualification — it *is* the
                    // visible lifetime of the pending query — so it starts here iff
                    // there is text, and dies on its own at the window's end.
                    if let pending = PendingQuery.snapshot(
                        query: query,
                        isCapturing: capture.isActive,
                        inFileSearch: inFileSearch,
                        autoSaveEnabled: pileAutoSave
                    ) {
                        PendingQueryStore.save(pending)
                    }
                    // The Live Activity is already live (it tracks the input —
                    // the `pendingActivityPreview` onChange below — so it shows
                    // without a request-at-background lag); backgrounding only
                    // arms its 30-second self-dismissal.
                    PendingQueryActivityController.armWindowDismissal()
                }
                if phase == .active {
                    // Resolve the Pending query first (issue #152): a ≥ 30s return
                    // must land on the clean Home *before* anything else reads
                    // `query`, and a < 30s cold launch restores the text into the
                    // input. Disarm the window dismissal — the return beat the
                    // window — and reconcile the activity with the resolved input:
                    // a restored query keeps it riding, a commit's cleared input
                    // ends it (`sync` is idempotent; the onChange below misses a
                    // resolution that leaves `query`'s value unchanged).
                    resolvePendingQuery(via: .plainOpen)
                    PendingQueryActivityController.cancelWindowDismissal()
                    PendingQueryActivityController.sync(preview: pendingActivityPreview)
                    fileIndex.rebuild(from: indexedFolders)
                    // Drain the Favorites widget's frecency outbox (ADR 0025; issue
                    // #126): credit each widget-run selection into `SignalsStore` at
                    // its recorded moment. Foreground is the drain point because
                    // the store loads once at launch and rewrites keys whole — the
                    // widget appending directly would be clobbered by the next save.
                    drainWidgetRuns()
                    // Re-fetch the Custom Action catalog so anything the Share
                    // Extension saved while backgrounded (a static link — ADR
                    // 0022/0030) appears in results (foreground re-index, no
                    // cross-process signal). Write the @State only when the
                    // catalog actually changed: an unconditional write
                    // invalidates the whole root on every activation — including
                    // the launch transition, where that no-op invalidation raced
                    // the first render (issue #112's near-deterministic CI crash
                    // on this branch). A failed fetch keeps the previous catalog —
                    // resetting to empty would drop already-merged rows.
                    if let fetched = try? modelContext.fetch(
                        FetchDescriptor<StoredCustomAction>(sortBy: [SortDescriptor(\.createdAt)])
                    ), fetched.map(\.id) != foregroundCustomActions.map(\.id) {
                        foregroundCustomActions = fetched
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
                case .editCustomAction(let action):
                    // The same live-mirroring editor the Custom Actions page presents,
                    // applying the edited definition to the stored record.
                    CustomActionEditorView(definition: action.definition, isNew: false) { def in
                        action.apply(def)
                    }
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
        case .customActions: CustomActionsView(enablement: instanceEnablement)
        case .fallbacks: FallbacksView(store: fallbacks, enablement: instanceEnablement, eligible: eligibleFallbackActions)
        case .snippets: SnippetManagerView(enablement: instanceEnablement)
        case .shortcuts: ShortcutsView(store: shortcuts, enablement: instanceEnablement)
        case .fileSearch: IndexedFoldersView(store: indexedFolders)
        // The Pile's settings page stays options-only (ADR 0018): its entries
        // are temporary content whose verbs — stage and discard — live on the
        // `.pile` entries page, the carve-out from the unified
        // content-under-options shape. Entries have no per-entry disable.
        case .pile, .calculator: ProviderOptionsPage(provider: provider)
        // Reminders and Events lead their Options with the reorderable capture-step
        // double-list (issue #145 follow-up) — the arrangeable steps beyond the pinned
        // Title — so they get a dedicated page rather than the options-only one.
        case .reminders:
            CaptureStepsPage<ReminderStep>(
                provider: .reminders,
                store: reminderSteps,
                stepsFooter: "The steps this capture collects after the title, in order. Turn a step off to skip it; drag to reorder. List on asks each time; off saves to the default list above."
            )
        case .events:
            CaptureStepsPage<EventStep>(
                provider: .events,
                store: eventSteps,
                stepsFooter: "The steps this capture collects after the title, in order. Turn a step off to skip it; drag to reorder. Start off makes the event all-day today; Calendar on asks each time; off saves to the default calendar above."
            )
        // The System umbrella page (ADR 0029): the cascading Enabled toggle and the
        // Reminders/Events link rows (its declared schema), plus an actions section
        // for its two disable-only built-ins.
        case .system: SystemView(enablement: instanceEnablement)
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

    /// Pins or unpins a Favorite (issue #9), with the firmer pin beat (ADR 0034) —
    /// the single toggle path both the Home grid and the Result list route through,
    /// so the deliberate commitment is felt wherever it's made.
    private func toggleFavorite(_ action: Action) {
        Haptics.play(.pinToggle)
        signals.toggleFavorite(action.id)
    }

    /// Runs a row's main action. A multi-step capture (New Reminder) begins its
    /// breadcrumb instead of performing an outcome straight away; everything else
    /// performs its `ActionOutcome` at the platform edge. Selecting an Action
    /// records a frecency event (issue #9 AC #2).
    private func run(_ action: Action) {
        // The light run beat (ADR 0034) on the single path every run funnels
        // through — a result-row tap, a Favorite tap, or Enter on the Highlighted
        // result — so the tap is felt whether it fires an outcome or opens a
        // breadcrumb. Later beats (a step's tick, a capture's confirmation) are the
        // policy's other moments, fired at their own sites.
        Haptics.play(.runAction)
        signals.record(action.id)
        // Selected from the bottom fallback region, a capture seeds-and-commits the
        // typed query as its first step — the free-text Title (issue #145 follow-up) —
        // so it continues at step 2; verb-first (a name match) it opens empty.
        if action.kind == .reminder {
            startReminderCapture(seed: fallbackSeed(for: action))
            return
        }
        if action.kind == .event {
            startEventCapture(seed: fallbackSeed(for: action))
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
    private func startReminderCapture(seed: String? = nil) {
        // The `-uitest-stub-reminders` seam: the same breadcrumb driven end-to-end
        // with only the EventKit edge stubbed, because XCUITest cannot pre-grant
        // the Reminders permission dialog (see `UITestReminderCapture`).
        if UITestReminderCapture.isRequested {
            capture.start(UITestReminderCapture(), layout: keyboardLayout.layout, seed: seed)
            return
        }
        capture.start(
            ReminderCapture(
                settings: ReminderSettings(
                    steps: CaptureStepPlan.resolved(reminderSteps.enabledRaw, as: ReminderStep.self),
                    listStored: reminderList
                )
            ),
            layout: keyboardLayout.layout,
            seed: seed
        )
    }

    /// Begins the New Event capture (issue #38): hand off to the same capture model
    /// New Reminder uses, configured with an `EventCapture` recipe. The recipe
    /// resolves EventKit calendar permission (primer → system dialog) just-in-time
    /// before the breadcrumb starts (ADR 0012), and routes editor mode through the
    /// shared `eventEditor` presenter. The search field keeps first responder for the
    /// same seamless keyboard hand-off as the reminder capture.
    private func startEventCapture(seed: String? = nil) {
        capture.start(
            EventCapture(
                settings: EventSettings(
                    steps: CaptureStepPlan.resolved(eventSteps.enabledRaw, as: EventStep.self),
                    calendarStored: eventCalendar,
                    useEditor: eventUseEditor
                ),
                presenter: eventEditor
            ),
            layout: keyboardLayout.layout,
            seed: seed
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
            // A main-action hand-off **resolves the query** (CONTEXT.md → Main
            // action; PR #151): clear back to Home so the text left behind can
            // never read as unresolved — a web search, a static Custom Action,
            // any filled URL template.
            openURL(url)
            query = ""
        case .copyText(let text):
            // A Snippet copy resolves the query too (same rule): the flash is
            // the acknowledgement, Home the landing.
            UIPasteboard.general.string = text
            flashConfirmation("Copied")
            query = ""
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
            // no app switch — clear to Home, and acknowledge like a copy-out. The
            // trim-and-drop-empty guard is the same Core rule the background Save for
            // later App Shortcut applies (issue #121), so the two write surfaces can't
            // diverge on what counts as an empty capture.
            if let entryText = HeadlineAppShortcut.pileText(fromDictated: text) {
                modelContext.insert(StoredPileEntry(text: entryText))
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
            // the capture and opens the same URL from `ShortcutCapture`. The
            // clear is **final** (CONTEXT.md → Main action): `x-error` flashes
            // its failure toast and `x-cancel` stays silent, neither restoring
            // the cleared text — the callback can land after the user has
            // started typing something new.
            openURL(ShortcutRun.runURL(name: name, input: input))
            query = ""
        case .none:
            break
        }
    }

    /// Performs a one-shot **secondary action** on a row (CONTEXT.md → Secondary
    /// action; ADR 0017). Core decides *which* verbs a row is eligible for; the App
    /// resolves the reference **at the edge** and runs the verb — the same
    /// defer-to-the-edge pattern as the main-action outcomes. The content verbs
    /// (copy/share/edit/reveal) only reach here for a content-bearing row, so an
    /// empty resolution is a stale reference, not a dead item; `copyDeeplink` is the
    /// exception — it rides on every row, keyed by the id, not the content.
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
            // app's editor by name; a Snippet and a Custom Action (slotted or static —
            // `.customAction`/`.quicklink` content, ADR 0030) each open their stored
            // record in the same in-app editor their library page uses.
            switch action.content {
            case .shortcut(let name):
                editShortcut(name)
            case .quicklink(let id), .customAction(let id):
                editCustomAction(id)
            default:
                editSnippet(action)
            }
        case .copyDeeplink:
            // Copy the row's tap-equivalent `quickie://run/<id>` URL, built by the
            // one pure constructor so the id is percent-encoded consistently (issue
            // #120). Available on every row, a content-less command included.
            UIPasteboard.general.string = QuickieDeeplink.runURL(id: action.id).absoluteString
            flashConfirmation("Copied deeplink")
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

    /// **Edit** a Custom Action (ADR 0017): resolves the row's `.customAction(id:)` or
    /// `.quicklink(id:)` content — a slotted action or a static (slot-less) link, both
    /// stored as `StoredCustomAction` (ADR 0030) — and opens the same live-mirroring
    /// editor the Custom Actions page uses, reached here straight from a result's
    /// long-press. Resolves against `indexedCustomActions` so a link the Share Extension
    /// just wrote (not yet in `@Query`) still edits. A stale id (the record was deleted)
    /// acknowledges rather than opening an empty editor.
    private func editCustomAction(_ id: String) {
        guard let action = indexedCustomActions.first(where: { $0.id == id }) else {
            flashConfirmation("Custom Action not found")
            return
        }
        activeSheet = .editCustomAction(action)
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
            // A bare `.url` value copies the string its open outcome would open —
            // except a Detected result row (Computed) opens a `tel:`/`sms:`/`mailto:`
            // URL whose *bare value* is the number or address the user typed, not the
            // scheme URI (CONTEXT.md → Detected result). `bareValue` reduces those to
            // the recipient and returns nil for a web URL, whose own string is already
            // the value — so an Open row still copies `https://apple.com`.
            if case .openURL(let url) = action.run(input: query) {
                return TypedContentDetector.bareValue(forDetectedURL: url) ?? url.absoluteString
            }
            return nil
        case .quicklink:
            // A Quicklink carries a real static URL; it copies exactly the string its
            // open outcome would open. Its `.quicklink` identity only adds Edit — it
            // changes nothing about what Copy resolves.
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
        case .none, .shortcut, .customAction:
            // None carries copyable text — a command/capture row has no content, a
            // Shortcut is a launchable reference, and a Custom Action's URL only
            // exists once its slots are filled: each offers Edit (or nothing), not Copy.
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
            // A bare `.url` value shares the URL its open outcome carries (the sheet
            // then offers link actions) — except a Detected result row's `tel:`/`sms:`/
            // `mailto:` URL shares as its bare number/address string instead, the value
            // the user typed (CONTEXT.md → Detected result); a web URL shares as a URL.
            if case .openURL(let url) = action.run(input: query) {
                if let bare = TypedContentDetector.bareValue(forDetectedURL: url) {
                    shareRequest = ShareRequest(items: [bare])
                } else {
                    shareRequest = ShareRequest(items: [url])
                }
            }
        case .quicklink:
            // A Quicklink shares the static URL its open outcome carries; its
            // `.quicklink` identity only adds Edit.
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
        case .none, .shortcut, .customAction:
            // Nothing to share — a content-less command row, a Shortcut (a launchable
            // reference), or a Custom Action (its URL exists only once filled): each
            // offers Edit (or nothing), not Share.
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

    /// Dispatches an inbound `quickie://` **deeplink** (issue #120; ADR 0024) — the
    /// door the App Intents bridge (#121) and epic #16's open-focused entry surfaces
    /// (#124, #125) ride. Both routes first **drop any scoped context** — a
    /// half-filled breadcrumb and the Search Files context — the same reset a
    /// Shortcut-output reinjection performs, so the app lands on the launcher root
    /// before acting:
    ///
    /// - `run/<id>` runs the resolved Action **tap-equivalently** (a Favorite's main
    ///   action, a Custom Action's breadcrumb, a quick-capture command row's capture —
    ///   `run/builtin.new-reminder` *is* "open the Reminder capture"); an id that no
    ///   longer resolves — unpinned, deleted, disabled — degrades to the clean Home
    ///   the reset already left, no error UI.
    /// - `entry` is the reset with **nothing selected after**, refocusing the input:
    ///   a fresh, focused Home for a warm app (cold launch already lands there).
    private func handleDeeplink(_ deeplink: QuickieDeeplink) {
        // Every deeplink is an Entry surface (CONTEXT.md → Entry surface):
        // "something new *now*", so a Pending query commits to the Pile at any
        // age — replacing the reset's old silent discard (issue #152) — before
        // the reset clears the input.
        commitPendingOnEntrySurface()
        resetToLauncher()
        switch deeplink {
        case .run(let id):
            // Tap-equivalent: behave exactly as if the user tapped this Action's
            // row. An unresolvable id leaves the clean Home the reset produced.
            if let action = engine.action(for: id) { run(action) }
        case .entry:
            // Fresh entry: the reset, then re-arm focus so the warm app lands on a
            // clean, focused Home exactly like a cold launch.
            refocusInput()
        }
    }

    /// Publishes the derived Bridged Action set for the App Intents bridge (issue
    /// #122; ADR 0024) and, **only when it actually changed**, nudges the system to
    /// re-read the parameterized "Run <name>" App Shortcut's options via
    /// `updateAppShortcutParameters()`. The `publish` write and the parameter refresh
    /// are paired so a no-op body pass costs nothing — the store guards the write and
    /// the refresh fires just once per real set change.
    @MainActor
    private func syncBridgedActions(_ actions: [BridgedAction]) {
        if BridgedActionStore.publish(actions) {
            QuickieAppShortcuts.updateAppShortcutParameters()
        }
    }

    /// The engine-derived **outward projections**, bundled so `body` observes them
    /// through a single `onChange`: the Bridged Action set the App Intents bridge
    /// publishes (issue #122), the Favorites widget snapshot (issue #126), and the
    /// eligible-action catalog the Actions widget and Action control join against
    /// (ADR 0027; #140). One value, not one observation each, because RootView's
    /// modifier chain sits near the compiler's type-checking budget (see the
    /// `onChange`).
    private struct OutwardProjections: Equatable {
        var bridged: [BridgedAction]
        var widgetFavorites: [WidgetAction]
        var catalog: [WidgetAction]
    }

    private var outwardProjections: OutwardProjections {
        OutwardProjections(
            bridged: engine.bridgedActions(),
            widgetFavorites: widgetFavoritesProjection,
            catalog: eligibleCatalogProjection
        )
    }

    /// The **Favorites widget** projection (ADR 0025; issue #126): the pinned grid
    /// exactly as Home renders it — `home()`'s favorites, so a disabled pin drops
    /// out here the moment it drops from the grid — denormalized per Favorite into
    /// id, title, badge glyph, kind, and the Core-classified execution. The widget
    /// draws and acts from this alone; the snippet *body* deliberately never rides
    /// along (the copy intent reads it fresh at run time — a stale snapshot must
    /// never copy stale text).
    private var widgetFavoritesProjection: [WidgetAction] {
        engine.home(showRecents: false).favorites.map { action in
            // A Custom Action's chosen glyph (issue #163) rides the snapshot so the
            // widget draws it from the projection alone; `nil` denormalizes the
            // kind-derived glyph, unchanged.
            WidgetAction(action: action, glyph: action.glyph ?? action.kind.symbol)
        }
    }

    /// Publishes the widget projection and, **only when it actually changed**,
    /// reloads the Favorites widget's timelines — the write/reload pairing ADR
    /// 0025 prescribes, mirroring `syncBridgedActions`' publish-then-nudge shape.
    @MainActor
    private func publishWidgetFavorites(_ favorites: [WidgetAction]) {
        if FavoritesWidgetStore.publish(favorites) {
            WidgetCenter.shared.reloadTimelines(ofKind: FavoritesWidgetStore.widgetKind)
        }
    }

    /// The **eligible-action catalog** projection (CONTEXT.md → Actions widget; ADR
    /// 0027; #140): every enabled Action except a Pile entry (`engine.eligibleActions()`),
    /// denormalized per Action into the same `WidgetAction` shape the Favorites
    /// snapshot uses — id, title, badge glyph, kind, Core-classified execution. The
    /// Actions widget picker enumerates this and both render surfaces join their
    /// configured ids against it. Derived from the live `engine`, so it moves with any
    /// create, edit, delete, enable, or disable that touches an eligible Action.
    private var eligibleCatalogProjection: [WidgetAction] {
        engine.eligibleActions().map { action in
            // A Custom Action's chosen glyph (issue #163) rides the catalog snapshot,
            // so the Actions widget and Action control render it; `nil` denormalizes
            // the kind-derived glyph.
            WidgetAction(action: action, glyph: action.glyph ?? action.kind.symbol)
        }
    }

    /// Publishes the eligible-action catalog and, **only when it actually changed**,
    /// reloads the Actions widget's timelines *and* the Action control — the two
    /// surfaces that join their configured ids against it, so a renamed, deleted, or
    /// (dis)abled action re-renders without the user re-opening a config sheet (ADR
    /// 0027). The same publish-then-reload pairing as `publishWidgetFavorites`.
    @MainActor
    private func publishEligibleCatalog(_ catalog: [WidgetAction]) {
        if EligibleActionCatalogStore.publish(catalog) {
            WidgetCenter.shared.reloadTimelines(ofKind: EligibleActionCatalogStore.widgetKind)
            ControlCenter.shared.reloadControls(ofKind: EligibleActionCatalogStore.controlKind)
        }
    }

    /// Drains the widget's pending run events into `SignalsStore` (ADR 0025; issue
    /// #126), each at its recorded moment so Frecency's decay sees when the run
    /// really happened. Consuming the outbox keeps Frecency single-writer: the
    /// widget only ever appends to its own key, and the app is the sole writer of
    /// the signals themselves.
    @MainActor
    private func drainWidgetRuns() {
        for event in FavoritesWidgetStore.drainRuns() {
            signals.record(event.actionID, at: event.date)
        }
    }

    /// Resolves the stored **Pending query** snapshot on activation (CONTEXT.md →
    /// Pending query; issue #152; ADR 0031). `take` consumes the snapshot, so each
    /// backgrounding is resolved exactly once even when activation and an
    /// entry-surface deeplink race for it. Within the window a plain open keeps
    /// the state — restoring the text into a cold launch's empty input (a warm
    /// resume still holds it live); at or past it, the scoped state resets to a
    /// clean Home and any pending text commits to the Pile with the flash.
    private func resolvePendingQuery(via path: PendingQueryReturn) {
        guard let pending = PendingQueryStore.take() else { return }
        switch pending.resolution(at: Date(), via: path) {
        case .keep:
            if let text = pending.text, isHome, !capture.isActive, !inFileSearch {
                query = text
            }
        case .reset(let commit):
            capture.cancel()
            inFileSearch = false
            query = ""
            if let commit { commitPendingToPile(commit) }
        }
    }

    /// Commits a Pending query on an Entry-surface arrival (issue #152): the
    /// stored snapshot when the deeplink won the race with activation, else the
    /// live input when activation already resolved (and possibly restored) it —
    /// or when the deeplink reached a foregrounded app. Either way the text
    /// lands in the Pile instead of the reset's silent discard; a breadcrumb or
    /// the Search Files filter still just resets, saving nothing.
    private func commitPendingOnEntrySurface() {
        if let pending = PendingQueryStore.take() {
            if case .reset(let commit) = pending.resolution(at: Date(), via: .entrySurface),
               let commit {
                commitPendingToPile(commit)
            }
            return
        }
        if let pending = PendingQuery.snapshot(
            query: query,
            isCapturing: capture.isActive,
            inFileSearch: inFileSearch,
            autoSaveEnabled: pileAutoSave
        ), let text = pending.text {
            commitPendingToPile(text)
        }
    }

    /// Writes an auto-saved Pending query into the Pile and flashes the preview
    /// confirmation (issue #152). Deliberately **no Frecency credit** (the
    /// auto-save is not a user selection) and **no dedupe** against existing
    /// entries (the manual Save for later doesn't either). The trim-and-drop-empty
    /// guard is the same Core rule every other Pile write surface applies.
    private func commitPendingToPile(_ text: String) {
        guard let entryText = HeadlineAppShortcut.pileText(fromDictated: text) else { return }
        modelContext.insert(StoredPileEntry(text: entryText))
        // Commit synchronously for the same invalidated-snapshot reason `stage`
        // does: the engine rebuilds off the `@Query` on the next keystroke.
        try? modelContext.save()
        flashConfirmation(PendingQuery.savedConfirmation(for: entryText))
    }

    /// Clears every scoped context back to the launcher root before a deeplink acts
    /// (issue #120): abandon an in-flight capture breadcrumb, leave the Search Files
    /// context, empty a stale query, and pop any pushed Management page. This is the
    /// open-focused entry-surface reset (CONTEXT.md → Entry surface) — a stale query
    /// cleared and a half-filled breadcrumb abandoned — shared by every deeplink so
    /// none of them acts on top of leftover state.
    private func resetToLauncher() {
        capture.cancel()
        inFileSearch = false
        query = ""
        if !path.isEmpty { path = [] }
    }

    /// The `-uitest-deeplink <url>` seam (issue #120): XCUITest cannot open a
    /// `quickie://` URL against the app, so a UI test passes one as a launch argument
    /// and the app dispatches it through the real `QuickieDeeplink.parse` →
    /// `handleDeeplink` path once the launcher appears. Gated on `--uitesting` so a
    /// stray flag can never fire in production, and latched so it runs a single time.
    private func dispatchUITestDeeplinkIfRequested() {
        guard !didDispatchLaunchDeeplink else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),
              let flagIndex = arguments.firstIndex(of: "-uitest-deeplink"),
              arguments.indices.contains(flagIndex + 1),
              let url = URL(string: arguments[flagIndex + 1]),
              let deeplink = QuickieDeeplink.parse(url)
        else { return }
        didDispatchLaunchDeeplink = true
        handleDeeplink(deeplink)
    }

    /// Drains a foreground headline App Shortcut's pending `quickie://` URL (issue
    /// #121; ADR 0024) and dispatches it through the real `QuickieDeeplink.parse →
    /// handleDeeplink` — the same door `onOpenURL` uses, so the routing logic stays
    /// in Core and there is no second inbound path. Consuming the inbox clears it, so
    /// this is safe to call from both `onChange` (warm hit) and `onAppear` (cold hit)
    /// and a stale route is never replayed.
    private func dispatchPendingDeeplink() {
        guard let url = deeplinkInbox.take(),
              let deeplink = QuickieDeeplink.parse(url)
        else { return }
        handleDeeplink(deeplink)
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
/// `editCustomAction` is the same **Edit** verb reaching a Custom Action's stored
/// record — slotted or a static (slot-less) link (ADR 0030) — opening the very editor
/// its library page uses, so a long-press edits an item without visiting its page.
private enum ActiveSheet: Identifiable {
    case composeSnippet(ComposeSeed)
    case editSnippet(StoredSnippet)
    case editCustomAction(StoredCustomAction)

    var id: String {
        switch self {
        case .composeSnippet(let seed): return "compose-snippet-\(seed.id)"
        case .editSnippet(let snippet): return "edit-snippet-\(snippet.id)"
        case .editCustomAction(let action): return "edit-custom-action-\(action.id)"
        }
    }
}

/// The Living backdrop the Liquid Glass chrome floats over (ADR 0010, 0034): a
/// still, subtle purple mesh field with one compact bloom ball sweeping slowly
/// up and down it on [[Home]], frozen the instant a query exists — alive at
/// rest, calm in use. The accent glow (here) and the gold hero glow
/// (`ResultListView`) sit over it unchanged, since a glow is backdrop content
/// the glass refracts, never overlaid blur.
private struct LivingBackdrop: View {
    /// How far up from the screen bottom to sit the accent glow's center — the
    /// bar's own held keyboard inset. Zero returns it to the bottom (no keyboard,
    /// or a pushed page), where the bar itself sits.
    ///
    /// The glow is anchored to the **bar**, not the screen, because the screen
    /// bottom is not a place the user ever looks: the keyboard covers the lower
    /// third from launch (the field is focused at zero-wall, ADR 0012), so a
    /// bottom-centered glow buries its own center and leaks only the faint outer
    /// edge of its falloff into view. Riding the bar puts the brightest point
    /// under the input and the [[Highlighted result]] above it — where the eye
    /// already is, and where there is glass to refract it, which is the entire
    /// job of a backdrop under ADR 0010.
    var glowLift: CGFloat = 0

    /// The drift period from Core's `MotionPolicy` — seconds for one full
    /// there-and-back sweep of the bloom ball — or `nil` for a still backdrop with
    /// the ball at its rest pose (a query exists, or Reduce Motion / Low Power
    /// Mode / UI test). The parent (`RootView.backdropDriftPeriod`) owns that
    /// decision, so "should drift" and "how fast" can never disagree here.
    var driftPeriod: Double?

    var body: some View {
        meshField
            .overlay { bloom }
            .overlay(alignment: .bottom) {
                // A steeper falloff than a plain two-stop gradient: most of the
                // fade happens in the first half of the radius, so the glow reads
                // as a localized pool of light under the bar rather than a broad
                // wash over the lower screen.
                RadialGradient(
                    stops: [
                        .init(color: Color.accentColor.opacity(0.14), location: 0),
                        .init(color: Color.accentColor.opacity(0.04), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.glowRadius
                )
                // Size the frame to the falloff's *diameter* and center the glow in
                // it, so the gradient reaches `.clear` exactly at its own top and
                // bottom edges — it can then be moved anywhere without showing one.
                // Insetting the frame instead (`.padding(.bottom, glowLift)`) puts
                // the center on the frame's edge, which cuts the glow off at full
                // strength and leaves a seam one `glowLift` tall under the bar. The
                // left/right edges are the screen's own, so they need no such care.
                .frame(height: Self.glowRadius * 2)
                // Bottom-aligned, the center lands `glowRadius` above the screen
                // bottom; this lands it on the bar. The motion is free: `glowLift`
                // is the bar's own held keyboard inset, so the glow rides the
                // keyboard's spring on show/hide and tracks the finger unanimated
                // through a swipe-dismiss, exactly like the bar it sits under.
                .offset(y: Self.glowRadius - glowLift)
                // Decorative: the backdrop must never take a touch meant for the chrome.
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    /// The quiet field the bloom sweeps over: a *static* mesh at one organic pose.
    /// The motion moved off the mesh entirely — a 3×3 mesh's control points sit
    /// ~half a screen apart, so any color lifted at one smears into a broad column
    /// no matter how its points travel, which is the opposite of the compact ball
    /// the backdrop should show. The mesh now only supplies the calm color wash.
    private var meshField: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: Self.meshPoints,
            colors: QuickieBrand.backdropMesh
        )
    }

    /// The travelling bloom — the one living element (ADR 0034). When there is a
    /// period its position is recomputed every frame from a `TimelineView(.animation)`
    /// clock; the cadence (the period) is still Core's single source of truth, and
    /// the timeline only supplies the frame clock. With no period the timeline is
    /// gone entirely, so a still backdrop costs zero redraws the moment a query
    /// exists.
    @ViewBuilder private var bloom: some View {
        if let driftPeriod {
            TimelineView(.animation) { context in
                bloomBall(
                    yPhase: Self.phase(at: context.date, period: driftPeriod),
                    xPhase: Self.phase(at: context.date, period: driftPeriod * Self.sidewaysPeriodRatio)
                )
            }
        } else {
            // At rest the ball sits centered on the screen's vertical axis
            // (xPhase 0.5 is the sideways oscillation's midpoint), near the top
            // of its vertical travel.
            bloomBall(yPhase: 0, xPhase: 0.5)
        }
    }

    /// A compact ball of brand violet fading to clear within its own radius — most
    /// of the fade in the first half, so it reads as a localized pool of color, not
    /// a wash. `yPhase` (0…1) sweeps it from near the top down past center — a
    /// travel of ~0.6 of the screen height; `xPhase` (0…1) wanders it a modest
    /// ~0.15-screen-width to either side of center.
    private func bloomBall(yPhase: Float, xPhase: Float) -> some View {
        GeometryReader { geo in
            RadialGradient(
                stops: [
                    .init(color: QuickieBrand.backdropBloom.opacity(0.85), location: 0),
                    .init(color: QuickieBrand.backdropBloom.opacity(0.25), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                center: .center,
                startRadius: 0,
                endRadius: Self.bloomRadius
            )
            // Size the frame to the falloff's diameter and position by center, so
            // the gradient reaches `.clear` exactly at its own edge and can sit
            // anywhere on screen without showing one (the same seam rule as the
            // accent glow below).
            .frame(width: Self.bloomRadius * 2, height: Self.bloomRadius * 2)
            .position(
                x: (0.5 + Self.sidewaysAmplitude * (2 * CGFloat(xPhase) - 1)) * geo.size.width,
                y: (0.15 + 0.65 * CGFloat(yPhase)) * geo.size.height
            )
        }
        .allowsHitTesting(false)
    }

    /// A smooth 0…1 oscillation over `period` seconds: a sine so the sweep eases at
    /// both turns with no seam where it reverses. One full rest→drift→rest cycle is
    /// `period`. Driven off the timeline's own clock, so it needs no stored phase.
    static func phase(at date: Date, period: Double) -> Float {
        let t = date.timeIntervalSinceReferenceDate
        return Float((sin(2 * .pi * t / period) + 1) / 2)
    }

    /// The nine control points of the static 3×3 field, row-major: corners pinned
    /// at the unit square, the interior row nudged off-grid so the wash keeps an
    /// organic tilt rather than reading as three flat bands.
    static let meshPoints: [SIMD2<Float>] = [
        SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
        SIMD2(0, 0.55), SIMD2(0.42, 0.48), SIMD2(1, 0.45),
        SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
    ]

    /// The travelling bloom's falloff radius — also half its frame, the seam rule
    /// above. Sized to read as an object crossing the screen, not a lighting
    /// change — but with real presence: 130 read as a dot lost on the field and
    /// 200 still too slight, so the ball's bright core spans most of the screen's
    /// width while the quick fade keeps its edge well inside the field.
    private static let bloomRadius: CGFloat = 280

    /// The sideways oscillation's period, as a multiple of the vertical one: the
    /// golden ratio, the most irrational of ratios — the two sines can never fall
    /// back into sync, so the ball's path never repeats a cycle. Against a
    /// divisible ratio (2×, 3×) the path closes into the same figure every few
    /// seconds and reads as a machine; this wanders, which is what makes it read
    /// as natural.
    private static let sidewaysPeriodRatio: Double = (1 + 5.0.squareRoot()) / 2

    /// How far the sideways wander reaches to either side of center, as a fraction
    /// of the screen's width. Modest on purpose: the vertical sweep is the motion,
    /// this only keeps it from riding a rail.
    private static let sidewaysAmplitude: CGFloat = 0.15

    /// The glow's falloff radius — also half its frame height, which is what keeps it
    /// seamless (see `body`).
    private static let glowRadius: CGFloat = 140
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
