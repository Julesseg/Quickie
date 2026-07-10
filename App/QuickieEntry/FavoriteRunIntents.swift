import AppIntents
import Foundation
import SwiftData
import UIKit
import QuickieCore
import QuickieStoreKit

/// The widget-surface button intents (ADR 0025; issue #126) — the execution edge of
/// the three-way split `WidgetExecution.classify` decides in Core. Named for their
/// origin (the Favorites widget) but **surface-agnostic**: the Actions widget and the
/// Action control (ADR 0027; #140) run their chosen Actions through these same three
/// intents and the same Frecency outbox, since every widget-grid cell and the control
/// execute the identical classified lane. The three are:
///
/// - `CopyFavoriteSnippetIntent` — the **in-place** lane: writes the pasteboard in
///   the widget process, no app launch.
/// - `OpenFavoriteIntent` — the **hand-off** lane: opens the classified URL (a
///   Quicklink's link, a Shortcut's x-callback run) via `OpenURLIntent`, straight
///   from the widget.
/// - `RunFavoriteInAppIntent` — the **open-app** lane (and the empty cells'
///   fresh-entry tap): foregrounds Quickie via `openAppWhenRun` and deposits the
///   Core-built `quickie://` route into `DeeplinkInbox` — the exact mechanism the
///   Control Center control rides (`QuickCaptureIntent`, #125). Deliberately NOT
///   an `OpenURLIntent` carrying `quickie://`: opening a custom scheme through it
///   from a widget is unreliable (universal links are its supported shape), and
///   the inbox deposit is this repo's proven door — `openAppWhenRun` runs
///   `perform()` in the **app's** process, so the deposit lands in the app's
///   inbox and `RootView` drains it through the single root parse → dispatch.
///
/// All three live in the folder synced into **both** the app and widget targets
/// (like `QuickCaptureIntent`): the system requires a widget intent that opens the
/// app to be compiled into both — a widget-only intent fails silently, a tap that
/// does nothing.
///
/// None are registered as App Shortcuts and `isDiscoverable = false` keeps them
/// out of the Shortcuts app's action list — the widget is their only surface.
///
/// **Frecency**: the copy and hand-off lanes append to the outbox
/// (`FavoritesWidgetStore.recordRun`) because the run completes without the app;
/// an open-app run is recorded by the app's ordinary tap path when the deeplink
/// resolves, so `RunFavoriteInAppIntent` never records — recording it there too
/// would double-count (ADR 0025).

/// **In-place copy** of a pinned Snippet (ADR 0025): writes the pasteboard from
/// the widget process with no app launch, reading the body **fresh from the
/// shared App Group store at run time** — never from the snapshot — so a stale
/// widget can never copy stale text.
struct CopyFavoriteSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Snippet"
    static let description = IntentDescription("Copy a pinned Snippet without opening Quickie.")
    static let isDiscoverable = false

    /// The Snippet's stable Action id (`snippet.<uuid>`) — the same reference the
    /// snapshot carries and the app's catalog indexes under.
    @Parameter(title: "Snippet")
    var actionID: String

    init() {}

    init(actionID: String) {
        self.actionID = actionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The shared store, CloudKit off — the extension side of the split the
        // Share Extension established (ADR 0022, 0023): only the app mirrors.
        // A store that won't open, or an id that no longer resolves (deleted
        // since the last snapshot rewrite — a vanishingly narrow race), degrades
        // to a silent no-op: never an error, and the next timeline reload fixes
        // the grid (ADR 0025).
        guard let container = try? QuickieStore.appGroupContainer(),
              let snippets = try? container.mainContext.fetch(FetchDescriptor<StoredSnippet>()),
              let snippet = snippets.first(where: { $0.actionID == actionID })
        else { return .result() }
        UIPasteboard.general.string = snippet.body
        // The run completed without the app, so credit Frecency through the
        // outbox — drained into `SignalsStore` on the app's next foreground.
        FavoritesWidgetStore.recordRun(actionID: actionID)
        return .result()
    }
}

/// **Direct hand-off** from the widget (ADR 0025): opens the classified URL — a
/// Quicklink's link in the browser, a no-input Shortcut's
/// `shortcuts://x-callback-url` run — via `OpenURLIntent`, the API that lets a
/// widget button open a URL without bouncing through Quickie. A Shortcut's
/// `quickie://` callbacks land in the app unchanged, exactly as an in-app run.
struct OpenFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Favorite"
    static let description = IntentDescription("Run a pinned Favorite from the widget.")
    static let isDiscoverable = false

    @Parameter(title: "URL")
    var url: URL

    /// The Action id credited in the frecency outbox — the hand-off completes
    /// outside the app, so the widget is the only place the run can be recorded.
    @Parameter(title: "Run Action ID")
    var runActionID: String?

    init() {}

    init(url: URL, recordingRunOf runActionID: String? = nil) {
        self.url = url
        self.runActionID = runActionID
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        if let runActionID {
            FavoritesWidgetStore.recordRun(actionID: runActionID)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// **Tap-equivalent open** (ADR 0025): the input-needing lane, and every empty
/// cell's fresh-entry tap. `openAppWhenRun` foregrounds Quickie and runs this in
/// the **app's** process, where the deposit lands in the app's `DeeplinkInbox`
/// for `RootView` to drain through the same `QuickieDeeplink.parse →
/// handleDeeplink` door as every other entry surface — no second inbound path
/// (ADR 0024), and an id that no longer resolves degrades to clean Home (#120).
struct RunFavoriteInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Quickie"
    static let description = IntentDescription("Open Quickie on a pinned Favorite.")
    static let isDiscoverable = false
    static let openAppWhenRun = true

    /// The Favorite's Action id for a tap-equivalent `quickie://run/<id>`, or
    /// `nil` for the clean, focused Home an empty cell opens (`quickie://entry`).
    @Parameter(title: "Action ID")
    var actionID: String?

    init() {}

    init(actionID: String?) {
        self.actionID = actionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = actionID.map { QuickieDeeplink.runURL(id: $0) } ?? QuickieDeeplink.entryURL()
        DeeplinkInbox.shared.deposit(url)
        return .result()
    }
}
