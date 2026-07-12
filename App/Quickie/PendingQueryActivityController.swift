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
    /// to sleep out the window and end it. `endAll` racing this (the user came
    /// back first) is fine — ending an ended activity is a no-op.
    private static func dismissAfterLifetime(_ activity: Activity<PendingQueryActivityAttributes>) {
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(taskID)
        }
        Task {
            try? await Task.sleep(for: .seconds(PendingQuery.lifetime))
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }
}
