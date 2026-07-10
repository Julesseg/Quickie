import EventKit
import QuickieCore

/// The EventKit edge for the New Reminder quick capture (issue #37): just-in-time
/// permission, the user's reminder lists as `ChoiceOption`s, and performing a
/// pure `ReminderDraft`. Kept entirely at the app boundary so `QuickieCore` never
/// imports EventKit — the same defer-to-the-edge pattern as the pasteboard.
///
/// An `actor` so the unbounded `EKEventStore.save` (an iCloud sync hiccup can
/// stall it) runs off the main thread, and the non-`Sendable` `EKEventStore`/
/// `EKReminder` stay confined to one isolation domain. The authorization-status
/// reads are `nonisolated` — they touch only the process-wide status, not the
/// store — so the capture's just-in-time branch can check them synchronously.
actor RemindersService {
    private let store = EKEventStore()

    /// Whether the user has refused access, so the capture can't proceed and the
    /// Action becomes an inline "Enable in Settings" affordance (ADR 0012). A
    /// not-yet-asked status is *not* denied — it is the cue to prime and request.
    nonisolated var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Whether access is already granted, so the capture can start straight away
    /// with no primer or system dialog.
    nonisolated var isAuthorized: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: return true
        default: return false
        }
    }

    /// Requests full access to reminders just-in-time, before any data entry (ADR
    /// 0012). Already-granted returns immediately; a refusal (or an unasked status
    /// the user then denies) returns `false`, which routes to the inline affordance.
    func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToReminders()) ?? false
        default:
            return false
        }
    }

    /// The user's modifiable reminder lists, as the choice options the list step
    /// fuzzy-matches over (CONTEXT.md → Reminder). The calendar identifier is the
    /// opaque `id` a `ReminderDraft.listID` carries back here.
    func reminderLists() -> [ChoiceOption] {
        store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ChoiceOption(id: $0.calendarIdentifier, label: $0.title) }
    }

    /// Performs a pure `ReminderDraft` against EventKit (CONTEXT.md → Reminder): a
    /// timed due date gets the full components *and* an absolute alarm so it
    /// notifies; a date-only due date gets day components with **no** alarm. A
    /// `nil` `listID` routes to the system default reminders list. Returns a deep
    /// link to the saved reminder so the confirmation toast can tap through to it.
    @discardableResult
    func create(_ draft: ReminderDraft) throws -> URL? {
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.calendar = calendar(for: draft.listID)
        reminder.notes = draft.notes
        reminder.priority = draft.priority

        if let due = draft.dueDate {
            let units: Set<Calendar.Component> = draft.hasTime
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if draft.hasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
        }

        try store.save(reminder, commit: true)
        return Self.deepLink(for: reminder)
    }

    /// A best-effort deep link to the saved reminder in the Reminders app. The
    /// `x-apple-reminderkit://REMCDReminder/<id>` scheme is the de-facto way to
    /// open a specific reminder — undocumented, so it is not guaranteed, but the
    /// scheme itself is registered, so a tap that can't resolve the id still lands
    /// in Reminders rather than failing.
    private static func deepLink(for reminder: EKReminder) -> URL? {
        let id = reminder.calendarItemIdentifier
        guard !id.isEmpty,
              let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return URL(string: "x-apple-reminderkit://") }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(encoded)")
    }

    /// The target list for a draft: the chosen list when it still exists, else the
    /// system default reminders list (the working default of ADR 0012).
    private func calendar(for listID: String?) -> EKCalendar? {
        if let listID, let match = store.calendar(withIdentifier: listID) {
            return match
        }
        return store.defaultCalendarForNewReminders()
    }
}
