import Foundation

/// How the New Event Action routes the event's target calendar (CONTEXT.md →
/// Event; issue #38), set by the user's default-calendar setting: `.ask` collects
/// it as a `choice` Argument per capture; `.fixed` skips that step and routes to a
/// preset calendar (a `nil` id meaning the system default calendar for new events).
public enum EventCalendarSelection: Equatable, Sendable {
    case ask
    case fixed(id: String?)

    /// Maps the calendar dynamic choice's stored value to a routing (ADR 0020;
    /// issue #69): empty is "Ask each time" (`.ask`); the system-default sentinel is
    /// "save silently to the system default calendar" (`.fixed(id: nil)`) — the state
    /// the old ask-off setting expressed; any other value is a fixed calendar id.
    public init(stored: String) {
        switch stored {
        case "": self = .ask
        case SettingsChoice.systemDefault: self = .fixed(id: nil)
        default: self = .fixed(id: stored)
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
    /// Free-text location for the event (issue #145), collected by the opt-in
    /// Location step → `EKEvent.location`. `nil` when the step is off or committed empty.
    public let location: String?
    /// Free-text notes for the event (issue #145), collected by the opt-in Notes
    /// step → `EKEvent.notes`. `nil` when the step is off or committed empty.
    public let notes: String?
    public let calendarID: String?

    public init(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String? = nil,
        notes: String? = nil,
        calendarID: String?
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarID = calendarID
    }
}

extension Action {
    /// The "New Event" quick-capture Action (CONTEXT.md → Event; issue #38): a
    /// verb-first, searchable Action that collects a **title**, a **start**, and a
    /// target **calendar** through the breadcrumb, reusing the #37 engine.
    ///
    /// Which steps it declares is the user's **step plan** (issue #145 follow-up): the
    /// enabled, ordered `steps` become breadcrumb steps after the pinned Title. A
    /// `.start` step collects the start; **absent**, the event is all-day today (from
    /// the injected `now` — the App passes the current date; Core stays clock-free). A
    /// `.calendar` step collects the target over `calendars` (ask each time); absent,
    /// the event routes to `calendarTarget` (a `nil` = the system default calendar).
    /// The `editor` setting (the silent-vs-editor preference, default **silent**)
    /// decides the final commit: silent resolves to `.createEvent` (a direct write),
    /// editor to `.composeEvent` (the pre-filled system event editor). The default plan
    /// (`EventStep.firstRun`) is Start then Calendar — today's flow.
    public static func newEvent(
        steps: [EventStep] = EventStep.firstRun,
        calendarTarget: String? = nil,
        calendars: [ChoiceOption] = [],
        now: Date = Date(timeIntervalSince1970: 0),
        editor: Bool = false
    ) -> Action {
        var arguments = [Argument(label: titleLabel, contentType: .text)]
        for step in steps {
            switch step {
            case .start:
                arguments.append(Argument(label: startLabel, contentType: .date))
            case .location:
                arguments.append(Argument(label: locationLabel, contentType: .text, isOptional: true))
            case .notes:
                arguments.append(Argument(label: notesLabel, contentType: .text, isOptional: true))
            case .calendar:
                arguments.append(Argument(
                    label: calendarLabel,
                    contentType: .text,
                    options: calendars,
                    optionSymbol: "calendar"
                ))
            }
        }

        // Bind the built-up steps to a `let` so the `@Sendable` effect captures an
        // immutable value (Swift 6 concurrency), and reads them back by label.
        let declared = arguments
        return Action(
            id: newEventID,
            kind: .event,
            title: "New Event",
            aliases: ["event", "calendar", "meeting", "appointment"],
            inputTypes: [.text],
            outputType: .text,
            arguments: declared,
            effect: { _ in .none },
            multiStepEffect: { values in
                let draft = draft(from: values, arguments: declared, calendarTarget: calendarTarget, now: now)
                return editor ? .composeEvent(draft) : .createEvent(draft)
            }
        )
    }

    // The step labels, shared by the Argument declaration and the by-label draft
    // reader (issue #145) so the two can never drift onto different strings.
    private static let titleLabel = "Title"
    private static let startLabel = "Start"
    private static let locationLabel = "Location"
    private static let notesLabel = "Notes"
    private static let calendarLabel = "Calendar"

    /// The stable id of the "New Event" capture command row. Exposed (like
    /// `saveForLaterID`) so the outward routes that steer this capture — the
    /// `quickie://run/<id>` deeplink and the New Event headline App Shortcut
    /// (issue #121; ADR 0024) — reference the same id the factory indexes it under,
    /// and can never drift from it.
    public static let newEventID = "builtin.new-event"

    /// The default duration of a timed event (CONTEXT.md → Event): one hour past
    /// the start. A date-only start ignores this and becomes all-day instead.
    private static let defaultDuration: TimeInterval = 60 * 60

    /// Builds the `EventDraft` from the collected Argument values (issue #38/#145),
    /// applying the timed-vs-all-day rule. Reads each field **by step label** against
    /// the declared `arguments`, so it is robust to any step plan — the two text steps
    /// (Location, Notes) no longer collide the way by-kind reading did. A Location or
    /// Notes step committed empty writes no field; an absent Calendar step falls back
    /// to `calendarTarget`. With **no** Start step the event is all-day at `now`; this
    /// same `now` fallback also keeps `mainAction`'s empty-values probe from trapping.
    private static func draft(
        from values: [ArgumentValue],
        arguments: [Argument],
        calendarTarget: String?,
        now: Date
    ) -> EventDraft {
        let title = values.text(labeled: titleLabel, in: arguments) ?? ""
        let calendarID = values.choiceID(labeled: calendarLabel, in: arguments) ?? calendarTarget
        let picked = values.date(labeled: startLabel, in: arguments)
        // Start collected → its date and time; no Start step (or the empty probe) →
        // all-day today from the injected clock.
        let start = picked?.date ?? now
        let hasTime = picked?.hasTime ?? false
        return EventDraft(
            title: title,
            start: start,
            end: hasTime ? start.addingTimeInterval(defaultDuration) : start,
            isAllDay: !hasTime,
            location: values.nonEmptyText(labeled: locationLabel, in: arguments),
            notes: values.nonEmptyText(labeled: notesLabel, in: arguments),
            calendarID: calendarID
        )
    }
}
