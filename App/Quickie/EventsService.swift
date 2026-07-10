import EventKit
import QuickieCore

/// The EventKit edge for the New Event quick capture (issue #38): just-in-time
/// permission, the user's writable calendars as `ChoiceOption`s, and performing a
/// pure `EventDraft` in silent mode. The editor-mode handoff lives in
/// `EventEditorView`, which builds its own main-thread store for the system editor;
/// this service owns only the silent path. Kept entirely at the app boundary so
/// `QuickieCore` never imports EventKit — the same defer-to-the-edge pattern as
/// `RemindersService`.
///
/// An `actor` so the unbounded `EKEventStore.save` (an iCloud sync hiccup can stall
/// it) runs off the main thread, and the non-`Sendable` `EKEventStore`/`EKEvent`
/// stay confined to one isolation domain. The authorization-status reads are
/// `nonisolated` — they touch only the process-wide status, not the store — so the
/// capture's just-in-time branch can check them synchronously.
actor EventsService {
    private let store = EKEventStore()

    /// Whether the user has refused calendar access, so the capture can't proceed
    /// and the Action becomes an inline "Enable in Settings" affordance (ADR 0012).
    /// A not-yet-asked status is *not* denied — it is the cue to prime and request.
    nonisolated var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Whether access is already granted, so the capture can start straight away
    /// with no primer or system dialog.
    nonisolated var isAuthorized: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return true
        default: return false
        }
    }

    /// Requests full access to calendar events just-in-time, before any data entry
    /// (ADR 0012). Already-granted returns immediately; a refusal (or an unasked
    /// status the user then denies) returns `false`, routing to the inline affordance.
    func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    /// The user's modifiable calendars, as the choice options the calendar step
    /// fuzzy-matches over (CONTEXT.md → Event). The calendar identifier is the
    /// opaque `id` an `EventDraft.calendarID` carries back here.
    func writableCalendars() -> [ChoiceOption] {
        store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { ChoiceOption(id: $0.calendarIdentifier, label: $0.title) }
    }

    /// Performs a pure `EventDraft` against EventKit in silent mode (CONTEXT.md →
    /// Event): a timed draft saves a one-hour event, a date-only draft an all-day
    /// one — the Core already resolved which from the picked start. A `nil`
    /// `calendarID` routes to the system default calendar for new events. Returns a
    /// best-effort deep link to the event's day so the confirmation toast can tap
    /// through to it.
    @discardableResult
    func create(_ draft: EventDraft) throws -> URL? {
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end
        event.location = draft.location
        event.notes = draft.notes
        event.calendar = calendar(for: draft.calendarID)

        try store.save(event, span: .thisEvent, commit: true)
        return Self.dayLink(for: draft.start)
    }

    /// A best-effort deep link that opens the Calendar app to the event's day. The
    /// `calshow:` scheme takes seconds since the 2001 reference date and lands on
    /// that day — there is no public per-event deep link, so the day is the closest
    /// tap-through the toast can offer.
    private static func dayLink(for start: Date) -> URL? {
        URL(string: "calshow:\(Int(start.timeIntervalSinceReferenceDate))")
    }

    /// The target calendar for a draft: the chosen calendar when it still exists,
    /// else the system default calendar for new events (the working default of ADR
    /// 0012).
    private func calendar(for calendarID: String?) -> EKCalendar? {
        if let calendarID, let match = store.calendar(withIdentifier: calendarID) {
            return match
        }
        return store.defaultCalendarForNewEvents
    }
}
