import AppIntents
import Foundation
import SwiftData
import UIKit
import QuickieCore
import QuickieStoreKit

/// The Favorites widget's two button intents (ADR 0025; issue #126) — the
/// execution edge of the three-way split `WidgetExecution.classify` decides in
/// Core. Between them they cover all three lanes:
///
/// - `CopyFavoriteSnippetIntent` — the **in-place** lane: writes the pasteboard in
///   the widget process, no app launch.
/// - `OpenFavoriteIntent` — the **hand-off** lane (a Quicklink's URL in the
///   browser, a Shortcut's x-callback run) *and* the **open-app** lane (a
///   `quickie://run/<id>` or `quickie://entry` the app resolves live): both are
///   "open this URL", differing only in whether the widget records the run.
///
/// Both live in the widget target only — unlike `QuickCaptureIntent` they are
/// never registered as App Shortcuts, so nothing outside the widget invokes them
/// (`isDiscoverable = false` keeps them out of the Shortcuts app's action list).
///
/// **Frecency**: the copy and hand-off lanes append to the outbox
/// (`FavoritesWidgetStore.recordRun`) because the run completes without the app;
/// an open-app run is recorded by the app's ordinary tap path when the deeplink
/// resolves, so `OpenFavoriteIntent` only records when told to — recording it
/// here too would double-count (ADR 0025).

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

/// Opens a URL from the widget — the **hand-off** lane (browser / Shortcuts app)
/// and the **open-app** lane (`quickie://` routes) of ADR 0025's split. Riding
/// `OpenURLIntent` keeps the buttons `Button(intent:)`-shaped in every family
/// (`Link` is unavailable in `systemSmall`), with one code path for both lanes.
struct OpenFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Favorite"
    static let description = IntentDescription("Run a pinned Favorite from the widget.")
    static let isDiscoverable = false

    @Parameter(title: "URL")
    var url: URL

    /// The Action id to credit in the frecency outbox, or `nil` when the run is
    /// recorded elsewhere: set for a hand-off (the run completes outside the
    /// app), `nil` for an open-app or empty-cell tap (the app's own tap path
    /// records resolved runs, and a fresh-entry open is not a selection at all).
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
