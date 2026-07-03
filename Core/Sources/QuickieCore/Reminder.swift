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
    public let listID: String?

    public init(title: String, dueDate: Date?, hasTime: Bool, listID: String?) {
        self.title = title
        self.dueDate = dueDate
        self.hasTime = hasTime
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
    /// due-date step (ADR 0012's working defaults keep it on), and `list == .ask`
    /// adds the list-choice step over the supplied `lists`. A `.fixed` list routes
    /// every reminder to a preset list with no step.
    public static func newReminder(
        askDate: Bool = true,
        list: ReminderListSelection = .fixed(id: nil),
        lists: [ChoiceOption] = []
    ) -> Action {
        var arguments = [Argument(label: "Title", contentType: .text)]
        if askDate {
            arguments.append(Argument(label: "Due Date", contentType: .date))
        }
        if case .ask = list {
            arguments.append(Argument(
                label: "List",
                contentType: .text,
                options: lists,
                optionSymbol: "list.bullet"
            ))
        }

        return Action(
            id: "builtin.new-reminder",
            kind: .reminder,
            title: "New Reminder",
            aliases: ["reminder", "remind me", "todo"],
            inputTypes: [.text],
            outputType: .text,
            arguments: arguments,
            effect: { _ in .none },
            multiStepEffect: { values in
                .createReminder(draft(from: values, list: list))
            }
        )
    }

    /// Builds the `ReminderDraft` from the collected Argument values (issue #37).
    /// Reads each field by value kind so it is robust to the steps a setting skips:
    /// the title is the text value, the list is the chosen option or the preset
    /// when that step was skipped.
    private static func draft(from values: [ArgumentValue], list: ReminderListSelection) -> ReminderDraft {
        let title = values.firstText ?? ""
        let listID = values.firstChoiceID ?? list.presetListID
        let due = values.firstDate
        return ReminderDraft(
            title: title,
            dueDate: due?.date,
            hasTime: due?.hasTime ?? false,
            listID: listID
        )
    }
}
