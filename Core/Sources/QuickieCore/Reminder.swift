import Foundation

/// How the New Reminder Action routes the reminder's target list (CONTEXT.md →
/// Reminder; issue #37), set by the user's default-list setting: `.ask` collects
/// it as a `choice` Argument per capture; `.fixed` skips that step and routes to a
/// preset list (a `nil` id meaning the system default reminders list).
public enum ReminderListSelection: Equatable, Sendable {
    case ask
    case fixed(id: String?)

    /// Maps the list dynamic choice's stored value to a routing (ADR 0020; issue
    /// #69): empty is "Ask each time" (`.ask`); the system-default sentinel is "save
    /// silently to the system default list" (`.fixed(id: nil)`) — the state the old
    /// ask-off setting expressed; any other value is a fixed list id.
    public init(stored: String) {
        switch stored {
        case "": self = .ask
        case SettingsChoice.systemDefault: self = .fixed(id: nil)
        default: self = .fixed(id: stored)
        }
    }

    /// The list id to bake in when this selection skips the list step — `nil`
    /// when the step is collected instead (`.ask`) or routed to the system default.
    var presetListID: String? {
        switch self {
        case .ask: return nil
        case .fixed(let id): return id
        }
    }
}

/// The pure description of a reminder to create (CONTEXT.md → Reminder; issue
/// #37), carried by `ActionOutcome.createReminder` for the app to perform against
/// EventKit. A `dueDate` with `hasTime` true gets an absolute alarm so it
/// notifies; a date-only due date (`hasTime` false) gets none. A `nil` `listID`
/// routes to the system default reminders list.
public struct ReminderDraft: Equatable, Sendable {
    public let title: String
    public let dueDate: Date?
    public let hasTime: Bool
    /// Free-text notes for the reminder (issue #145), collected by the opt-in Notes
    /// step → `EKReminder.notes`. `nil` when the step is off or committed empty.
    public let notes: String?
    /// The reminder's priority (issue #145) in EventKit's scale: 0 none, then 1 High,
    /// 5 Medium, 9 Low — collected by the opt-in Priority step. Defaults to 0 (none)
    /// when the step is off, matching a reminder created with no priority set.
    public let priority: Int
    public let listID: String?

    public init(
        title: String,
        dueDate: Date?,
        hasTime: Bool,
        notes: String? = nil,
        priority: Int = 0,
        listID: String?
    ) {
        self.title = title
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.notes = notes
        self.priority = priority
        self.listID = listID
    }
}

extension Action {
    /// The "New Reminder" quick-capture Action (CONTEXT.md → Reminder; issue #37):
    /// a verb-first, searchable Action that collects a **title**, an optional
    /// **due date**, and a target **list** through the breadcrumb, then resolves
    /// to a pure `createReminder` outcome the app performs against EventKit.
    ///
    /// Which steps it declares is gated by the user's settings: `askDate` adds the
    /// due-date step (ADR 0012's working defaults keep it on), the opt-in `askNotes`
    /// and `askPriority` add the Notes and Priority steps (issue #145, both off by
    /// default), and `list == .ask` adds the list-choice step over the supplied
    /// `lists`. A `.fixed` list routes every reminder to a preset list with no step.
    /// Step order: Title → Due Date → Notes → Priority → List.
    public static func newReminder(
        askDate: Bool = true,
        askNotes: Bool = false,
        askPriority: Bool = false,
        list: ReminderListSelection = .fixed(id: nil),
        lists: [ChoiceOption] = []
    ) -> Action {
        var arguments = [Argument(label: titleLabel, contentType: .text)]
        if askDate {
            arguments.append(Argument(label: dueDateLabel, contentType: .date))
        }
        if askNotes {
            arguments.append(Argument(label: notesLabel, contentType: .text, isOptional: true))
        }
        if askPriority {
            arguments.append(Argument(
                label: priorityLabel,
                contentType: .text,
                options: priorityOptions,
                optionSymbol: "exclamationmark"
            ))
        }
        if case .ask = list {
            arguments.append(Argument(
                label: listLabel,
                contentType: .text,
                options: lists,
                optionSymbol: "list.bullet"
            ))
        }

        // Bind the built-up steps to a `let` so the `@Sendable` effect captures an
        // immutable value (Swift 6 concurrency), and reads them back by label.
        let steps = arguments
        return Action(
            id: newReminderID,
            kind: .reminder,
            title: "New Reminder",
            aliases: ["reminder", "remind me", "todo"],
            inputTypes: [.text],
            outputType: .text,
            arguments: steps,
            effect: { _ in .none },
            multiStepEffect: { values in
                .createReminder(draft(from: values, arguments: steps, list: list))
            }
        )
    }

    // The step labels, shared by the Argument declaration and the by-label draft
    // reader (issue #145) so the two can never drift onto different strings.
    private static let titleLabel = "Title"
    private static let dueDateLabel = "Due Date"
    private static let notesLabel = "Notes"
    private static let priorityLabel = "Priority"
    private static let listLabel = "List"

    /// The Priority step's choice options (issue #145): the user-facing names mapped
    /// to EventKit's `EKReminder.priority` scale as each option's id — None 0, Low 9,
    /// Medium 5, High 1 — so the draft reads the picked id straight back as the value.
    private static let priorityOptions = [
        ChoiceOption(id: "0", label: "None"),
        ChoiceOption(id: "9", label: "Low"),
        ChoiceOption(id: "5", label: "Medium"),
        ChoiceOption(id: "1", label: "High"),
    ]

    /// The stable id of the "New Reminder" capture command row. Exposed (like
    /// `saveForLaterID`) so the outward routes that steer this capture — the
    /// `quickie://run/<id>` deeplink and the New Reminder headline App Shortcut
    /// (issue #121; ADR 0024) — reference the same id the factory indexes it under,
    /// and can never drift from it.
    public static let newReminderID = "builtin.new-reminder"

    /// Builds the `ReminderDraft` from the collected Argument values (issue #37/#145).
    /// Reads each field **by step label** against the declared `arguments`, so it is
    /// robust to any toggle combination — two text steps (Title, Notes) and two
    /// choice steps (Priority, List) no longer collide the way by-kind reading did.
    /// A Notes step committed empty writes no notes; an absent Priority step is 0
    /// (none); a skipped List step falls back to the preset routing.
    private static func draft(
        from values: [ArgumentValue],
        arguments: [Argument],
        list: ReminderListSelection
    ) -> ReminderDraft {
        let title = values.text(labeled: titleLabel, in: arguments) ?? ""
        let due = values.date(labeled: dueDateLabel, in: arguments)
        let priority = values.choiceID(labeled: priorityLabel, in: arguments).flatMap { Int($0) } ?? 0
        let listID = values.choiceID(labeled: listLabel, in: arguments) ?? list.presetListID
        return ReminderDraft(
            title: title,
            dueDate: due?.date,
            hasTime: due?.hasTime ?? false,
            notes: values.nonEmptyText(labeled: notesLabel, in: arguments),
            priority: priority,
            listID: listID
        )
    }
}
