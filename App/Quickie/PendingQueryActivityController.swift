import Foundation
import UIKit
import ActivityKit
import QuickieCore

/// Starts and ends the Pending-query Live Activity (issue #152) at the app
/// edge. The activity **is the visible lifetime of the pending query**: it
/// starts on backgrounding when a qualifying query is pending, dies on its own
/// at the 30-second mark (when the query has expired to the Pile, committed on
/// next activation), and ends immediately whenever the app foregrounds by any
/// path — the pending question is resolved at that moment, whichever way.
///
/// The self-dismissal rides the ~30 seconds of background execution
/// `beginBackgroundTask` grants after backgrounding — comfortably covering the
/// window without a scheduled wake (ADR 0031 rejects background timers for the
/// *commit*; this task only removes chrome). If the system terminates the app
/// inside the window anyway, the activity lingers stale until the next open
/// ends it — text is never lost either way, because the commit decision never
/// depends on this code running.
@MainActor
enum PendingQueryActivityController {
    /// Starts the activity for a qualifying pending query and arms its
    /// 30-second self-dismissal. Any previous activity is ended first so at
    /// most one is ever live — one pending query, one activity.
    static func start(preview: String) {
        endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: PendingQueryActivityAttributes.ContentState(preview: preview),
            staleDate: Date().addingTimeInterval(PendingQuery.lifetime)
        )
        guard let activity = try? Activity.request(
            attributes: PendingQueryActivityAttributes(),
            content: content
        ) else { return }
        dismissAfterLifetime(activity)
    }

    /// Ends every live Pending-query activity immediately — the foreground
    /// path: however the user came back, the pending question is resolved now.
    static func endAll() {
        for activity in Activity<PendingQueryActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Removes the activity at the window's end without the app running in the
    /// foreground: a background task keeps the process alive just long enough
    /// to sleep out the window and end it. The grant is itself only ~30
    /// seconds — it can expire *before* the sleep completes — so the
    /// expiration handler ends the activity too (a touch early beats lingering
    /// stale). Every path racing another (`endAll` on a quick return, the
    /// handler vs. the sleep) is fine: ending an ended activity is a no-op,
    /// and `endDismissalTask` guards the one-shot task release.
    private static func dismissAfterLifetime(_ activity: Activity<PendingQueryActivityAttributes>) {
        endDismissalTask()
        dismissalTaskID = UIApplication.shared.beginBackgroundTask {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            Task { @MainActor in endDismissalTask() }
        }
        Task {
            try? await Task.sleep(for: .seconds(PendingQuery.lifetime))
            await activity.end(nil, dismissalPolicy: .immediate)
            endDismissalTask()
        }
    }

    /// The one live dismissal grant — at most one activity exists at a time
    /// (`start` ends any predecessor), so a single identifier suffices.
    private static var dismissalTaskID = UIBackgroundTaskIdentifier.invalid

    /// Releases the grant exactly once: the sleep path, the expiration handler,
    /// and a re-`start` can all reach here, and `endBackgroundTask` must not be
    /// called twice for one identifier.
    private static func endDismissalTask() {
        guard dismissalTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(dismissalTaskID)
        dismissalTaskID = .invalid
    }
}
