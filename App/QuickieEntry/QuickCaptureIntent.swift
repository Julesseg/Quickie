import AppIntents
import QuickieCore

/// **Quick Capture** — opens the app on a clean, focused Home via `quickie://entry`
/// (CONTEXT.md → Entry surface). Cold launch already auto-focuses (ADR 0012); riding
/// the entry reset makes the *warm* case abandon stale state instead of resuming it.
///
/// This is the single Quick Capture intent shared by **both** entry surfaces that
/// invoke it (issue #125): the headline App Shortcut (#121, registered by the app's
/// `QuickieAppShortcuts`) *and* the Control Center control (`QuickCaptureControl` in
/// the widget extension). It lives in a folder synced into both the app and widget
/// targets so the control can ride the exact same intent — one intent, one inbound
/// door, no parallel path (ADR 0024). It carries no routing logic of its own: it only
/// deposits the Core-built `quickie://entry` URL into `DeeplinkInbox` for `RootView`
/// to drain through the single root `onOpenURL`.
struct QuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription(
        "Open Quickie on a fresh, focused Home, ready for a new query."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openInApp(.quickCapture)
        return .result()
    }
}

extension AppIntent {
    /// Deposit a foreground verb's Core-built `quickie://` URL for `RootView` to
    /// dispatch through the single root `onOpenURL` path (ADR 0024). Every foreground
    /// verb has a non-nil `deeplinkURL`, so the guard below is unreachable in correct
    /// use; it only trips if a *background* verb (Save for later) is wired here by
    /// mistake, which the Core type's split shape prevents. That is a programmer
    /// error, not a runtime condition, so it trips `assertionFailure` — a debug trap
    /// that is compiled out in Release, where the call then no-ops rather than opening
    /// anything (acceptable because it cannot happen given the fixed foreground set).
    @MainActor
    func openInApp(_ shortcut: HeadlineAppShortcut) {
        guard let url = shortcut.deeplinkURL else {
            assertionFailure("\(shortcut) is a background verb with no deeplink to open")
            return
        }
        DeeplinkInbox.shared.deposit(url)
    }
}
