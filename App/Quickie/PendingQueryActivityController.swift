import Foundation
import UIKit
import ActivityKit
import QuickieCore

/// Starts, updates, and ends the Pending-query Live Activity (issue #152) at
/// the app edge. The activity mirrors the **unresolved input itself**, not the
/// backgrounding: it starts the moment the root input holds a qualifying query
/// and ends the moment that query empties or a result's main action resolves
/// it — so when the user leaves mid-thought the activity is already live and
/// appears without the request-at-background lag. Backgrounding only **arms
/// the 30-second window dismissal**: the activity dies on its own at the
/// window's edge (when the query has expired to the Pile, committed on next
/// activation); a return within the window disarms it and the activity rides
/// on with the still-pending query.
///
/// The self-dismissal rides the ~30 seconds of background execution
/// `beginBackgroundTask` grants after backgrounding — comfortably covering the
/// window (ADR 0031 rejects background timers for the *commit*; this task only
/// removes chrome). If the system suspends or terminates the app inside the
/// window anyway, the expiration handler ends the activity a touch early, and
/// a leftover from a killed process is reconciled by the next launch's `sync`
/// — text is never lost either way, because the commit decision never depends
/// on this code running.
@MainActor
enum PendingQueryActivityController {
    /// The activity this process requested, when it did. `liveActivity()`
    /// falls back to the system's list so a prior process's activity is
    /// adopted (updated/ended) rather than orphaned.
    private static var current: Activity<PendingQueryActivityAttributes>?
    /// The armed window-dismissal sleep, cancelled when the user returns
    /// within the window.
    private static var dismissal: Task<Void, Never>?
    /// The one live background-task grant keeping the dismissal sleep running.
    private static var dismissalTaskID = UIBackgroundTaskIdentifier.invalid

    /// Reconciles the activity with the current pending preview: text starts
    /// one (or updates the live one's preview as the user types); `nil` — the
    /// input emptied, a main action resolved the query, a capture or the
    /// Search Files context took over, or the toggle is off — ends it.
    /// Idempotent, so activation paths can call it defensively.
    static func sync(preview: String?) {
        guard let preview else {
            endAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: PendingQueryActivityAttributes.ContentState(preview: preview),
            staleDate: nil
        )
        if let activity = liveActivity() {
            Task { await activity.update(content) }
        } else {
            current = try? Activity.request(
                attributes: PendingQueryActivityAttributes(),
                content: content
            )
        }
    }

    /// Ends every live Pending-query activity immediately and disarms any
    /// pending window dismissal.
    static func endAll() {
        cancelWindowDismissal()
        current = nil
        for activity in Activity<PendingQueryActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Arms the 30-second self-dismissal on backgrounding: stamp the window's
    /// end as the activity's stale date and sleep it out under a background
    /// task, ending the activity when the window closes without a return. The
    /// grant is itself only ~30 seconds — it can expire *before* the sleep
    /// completes — so the expiration handler ends the activity too (a touch
    /// early beats lingering stale). No-op without a live activity.
    static func armWindowDismissal() {
        cancelWindowDismissal()
        guard let activity = liveActivity() else { return }
        let content = ActivityContent(
            state: activity.content.state,
            staleDate: Date().addingTimeInterval(PendingQuery.lifetime)
        )
        Task { await activity.update(content) }
        dismissalTaskID = UIApplication.shared.beginBackgroundTask {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            Task { @MainActor in endDismissalTask() }
        }
        dismissal = Task {
            try? await Task.sleep(for: .seconds(PendingQuery.lifetime))
            guard !Task.isCancelled else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
            endDismissalTask()
        }
    }

    /// Disarms the window dismissal on a return within the window: the query
    /// is restored (or was never gone), so the activity rides on with it.
    static func cancelWindowDismissal() {
        dismissal?.cancel()
        dismissal = nil
        endDismissalTask()
    }

    /// The activity to update or end: this process's, else one adopted from
    /// the system's list (a prior process requested it and was killed).
    private static func liveActivity() -> Activity<PendingQueryActivityAttributes>? {
        if let current, current.activityState == .active { return current }
        return Activity<PendingQueryActivityAttributes>.activities
            .first { $0.activityState == .active }
    }

    /// Releases the grant exactly once: the sleep path, the expiration handler,
    /// and a disarm can all reach here, and `endBackgroundTask` must not be
    /// called twice for one identifier.
    private static func endDismissalTask() {
        guard dismissalTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(dismissalTaskID)
        dismissalTaskID = .invalid
    }
}
