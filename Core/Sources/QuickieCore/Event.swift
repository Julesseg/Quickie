import Foundation

/// How the New Event Action routes the event's target calendar (CONTEXT.md →
/// Event; issue #38), set by the user's default-calendar setting: `.ask` collects
/// it as a `choice` Argument per capture; `.fixed` skips that step and routes to a
/// preset calendar (a `nil` id meaning the system default calendar for new events).
public enum EventCalendarSelection: Equatable, Sendable {
    case ask
    case fixed(id: String?)

    /// The calendar id to bake in when this selection skips the calendar step —
    /// `nil` when the step is collected instead (`.ask`) or routed to the default.
    var presetCalendarID: String? {
        switch self {
        case .ask: return nil
        case .fixed(let id): return id
        }
    }
}

/// The pure description of a calendar event to create (CONTEXT.md → Event; issue
/// #38), carried by `ActionOutcome.createEvent`/`.composeEvent` for the app to
/// perform against EventKit. A timed start gets a default **one-hour** duration
/// (`isAllDay` false, `end` an hour past `start`); a date-only start becomes an
/// **all-day** event (`isAllDay` true). A `nil` `calendarID` routes to the system
/// default calendar for new events.
public struct EventDraft: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarID: String?

    public init(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
    }
}

extension Action {
    /// The "New Event" quick-capture Action (CONTEXT.md → Event; issue #38): a
    /// verb-first, searchable Action that collects a **title**, a **start**, and a
    /// target **calendar** through the breadcrumb, reusing the #37 engine.
    ///
    /// Unlike a reminder's optional due date, the start is **always** collected — an
    /// event has to happen somewhere on the calendar. The `calendar` setting gates
    /// the calendar-choice step; a `.fixed` calendar routes every event to a preset
    /// one with no step. The `editor` setting (the silent-vs-editor preference,
    /// default **silent**) decides the final commit: silent resolves to
    /// `.createEvent` (a direct write), editor to `.composeEvent` (the pre-filled
    /// system event editor for final review). Both collect the same breadcrumb.
    public static func newEvent(
        calendar: EventCalendarSelection = .fixed(id: nil),
        calendars: [ChoiceOption] = [],
        editor: Bool = false
    ) -> Action {
        var arguments = [
            Argument(label: "Title", contentType: .text),
            Argument(label: "Start", contentType: .date),
        ]
        if case .ask = calendar {
            arguments.append(Argument(
                label: "Calendar",
                contentType: .text,
                options: calendars,
                optionSymbol: "calendar"
            ))
        }

        return Action(
            id: "builtin.new-event",
            kind: .event,
            title: "New Event",
            aliases: ["event", "calendar", "meeting", "appointment"],
            inputTypes: [.text],
            outputType: .text,
            arguments: arguments,
            effect: { _ in .none },
            multiStepEffect: { values in
                let draft = draft(from: values, calendar: calendar)
                return editor ? .composeEvent(draft) : .createEvent(draft)
            }
        )
    }

    /// The default duration of a timed event (CONTEXT.md → Event): one hour past
    /// the start. A date-only start ignores this and becomes all-day instead.
    private static let defaultDuration: TimeInterval = 60 * 60

    /// Builds the `EventDraft` from the collected Argument values (issue #38),
    /// applying the timed-vs-all-day rule. Reads each field by value kind so it is
    /// robust to the calendar step a setting skips: the title is the text value, the
    /// calendar is the chosen option or the preset when that step was skipped.
    private static func draft(from values: [ArgumentValue], calendar: EventCalendarSelection) -> EventDraft {
        let title = values.firstText ?? ""
        let calendarID = values.firstChoiceID ?? calendar.presetCalendarID
        let picked = values.firstDate
        // The start is required, but `mainAction` probes with empty values to read
        // the outcome *case*; fall back to the epoch so that probe never traps.
        let start = picked?.date ?? Date(timeIntervalSince1970: 0)
        let hasTime = picked?.hasTime ?? false
        return EventDraft(
            title: title,
            start: start,
            end: hasTime ? start.addingTimeInterval(defaultDuration) : start,
            isAllDay: !hasTime,
            calendarID: calendarID
        )
    }
}
