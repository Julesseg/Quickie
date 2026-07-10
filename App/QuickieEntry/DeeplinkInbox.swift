import Foundation
import QuickieCore

/// The hand-off a **foreground** headline App Shortcut (issue #121; ADR 0024) uses
/// to steer the running app, without opening a second inbound path. The App Intent
/// can't reach into `RootView`, and it must not carry routing logic of its own
/// (ADR 0024 rejects an in-process router stranded outside Core's test gate), so it
/// only deposits the Core-built `quickie://` URL here; `RootView` drains it through
/// the *same* `QuickieDeeplink.parse → handleDeeplink` the root `onOpenURL` runs.
///
/// A process-global singleton because the intent and the view never share an
/// instance any other way, and — on a cold launch the intent triggers — the URL is
/// deposited before `RootView` exists. `RootView` therefore both observes `pending`
/// (a warm hit lands after it's on screen) and drains it on appear (a cold hit
/// landed before), consuming it once so a relaunch can't replay a stale route.
@Observable
@MainActor
final class DeeplinkInbox {
    static let shared = DeeplinkInbox()

    /// The `quickie://` URL a foreground intent asked the app to open, or `nil`
    /// when there is nothing pending. Cleared by `take()` the instant it's consumed.
    private(set) var pending: URL?

    private init() {}

    /// Deposit a URL for `RootView` to dispatch. Called from an App Intent's
    /// `perform()` after it foregrounds the app.
    func deposit(_ url: URL) {
        pending = url
    }

    /// Consume the pending URL, clearing it so it dispatches exactly once. Returns
    /// `nil` when nothing is waiting.
    func take() -> URL? {
        defer { pending = nil }
        return pending
    }
}
