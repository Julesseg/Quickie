import Foundation

/// One option in a `choice` Argument's fixed set (issue #37) — e.g. a user's
/// EventKit reminder list. The Core carries only an opaque `id` plus the `label`
/// shown and matched; the app maps its domain objects (an `EKCalendar`) to these
/// and resolves the chosen `id` back when performing the outcome.
public struct ChoiceOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// A value committed for an Argument — what a sealed breadcrumb pill carries
/// (issue #37). Each case is the result of one input method: free `text`, a
/// picked `date` (with whether the user included a time, which decides a
/// reminder's alarm), or a selected `choice` option.
public enum ArgumentValue: Equatable, Sendable {
    case text(String)
    case date(Date, hasTime: Bool)
    case choice(ChoiceOption)
}

/// Which system keyboard a `keyboard` input method raises (issue #96): the
/// default alphanumeric layout for free `text`, or the numeric layout for a
/// `number` Argument so it comes up on the number pad. A *variant* of one input
/// method rather than a separate method — it is still the keyboard, only laid out
/// differently — and, like every other input method, it is declaration-driven
/// (derived from the Argument's content type, never set by hand).
public enum KeyboardVariant: Equatable, Sendable {
    case text
    case number
}

/// The control the single bottom input morphs into for an Argument (CONTEXT.md →
/// Input method; ADR 0013). Derived from the Argument's content type and option
/// set so the control can never drift from the data: a fixed option set is always
/// a fuzzy `choice`, a `date` is the in-place picker, a `number` raises the keyboard
/// in its numeric variant, and everything else the keyboard in its text variant.
public enum InputMethod: Equatable, Sendable {
    case keyboard(KeyboardVariant)
    case datePicker
    case choice([ChoiceOption])
}

/// One ordered, typed slot a multi-step Action collects through the breadcrumb
/// (CONTEXT.md → Argument). It declares a display `label` (the pill prompt) and a
/// `contentType`; a `choice` slot additionally carries its fixed `options`. The
/// `inputMethod` is computed, never stored, so it stays in lock-step with the
/// declaration.
public struct Argument: Equatable, Sendable {
    public let label: String
    public let contentType: ContentType
    /// The fixed option set for a choice Argument; empty for keyboard/date slots.
    public let options: [ChoiceOption]
    /// The glyph each of this choice step's option rows shows — a reminder list's
    /// bullet, an event calendar's calendar (issue #38). Carried here so the icon is
    /// declared with the step rather than hard-coded in the view; `nil` for non-choice
    /// steps, and the app falls back to a sensible default when a choice step omits it.
    public let optionSymbol: String?
    /// For a `date` Argument, whether the picker collects a **time** as well —
    /// restricting the control with no in-picker toggle (issue #96): a Custom Action's
    /// date slot sets this from its format's meaning (date vs datetime). `nil` (the
    /// default) leaves it **user-choosable** — the New Reminder / Event date steps keep
    /// their "Include a time" toggle, which decides a reminder's alarm. Ignored by
    /// non-date Arguments.
    public let dateIncludesTime: Bool?
    /// Whether this Argument may be **committed empty** (issue #46): the user can
    /// submit the step with no value and the Action still runs — a Shortcut Action's
    /// optional `text` input. Defaults to `false`: most Arguments are required, so an
    /// empty commit is ignored (the generic capture keeps the user on the step). Only
    /// the free-text (`keyboard`) input method honours this; a `date` always carries a
    /// value and a `choice` commits a picked option.
    public let isOptional: Bool

    public init(
        label: String,
        contentType: ContentType,
        options: [ChoiceOption] = [],
        optionSymbol: String? = nil,
        dateIncludesTime: Bool? = nil,
        isOptional: Bool = false
    ) {
        self.label = label
        self.contentType = contentType
        self.dateIncludesTime = dateIncludesTime
        self.options = options
        self.optionSymbol = optionSymbol
        self.isOptional = isOptional
    }

    /// Which control the input region presents for this Argument (ADR 0013): a
    /// fixed option set is a fuzzy choice, a `date` is the picker, a `number`
    /// raises the numeric keyboard variant, and anything else the text keyboard.
    public var inputMethod: InputMethod {
        if !options.isEmpty { return .choice(options) }
        switch contentType {
        case .date: return .datePicker
        case .number: return .keyboard(.number)
        default: return .keyboard(.text)
        }
    }
}

/// Reads a collected breadcrumb's first text value (issue #37/#46) — what a
/// single-text-step capture (a Shortcut Action's lone optional input) uses to pull
/// its field. Robust to a *skipped* step, but not to a **second step of the same
/// kind**: a capture with more than one text or choice step reads by label instead
/// (the by-label readers below, issue #145).
extension Array where Element == ArgumentValue {
    var firstText: String? {
        for case .text(let s) in self { return s }
        return nil
    }
}

/// Reads a collected breadcrumb's values back out **by step label** (issue #145) —
/// what a quick-capture with more than one step of the same kind uses to pull each
/// field. The pills are collected in Argument order, so a step's value sits at its
/// declared index; resolving by label against the same `arguments` the capture
/// declared keeps this robust to any toggle combination — a skipped step is simply
/// absent from `arguments`, and every remaining step still lands on its own value.
extension Array where Element == ArgumentValue {
    /// The value committed for the step declared with `label`, or `nil` when that
    /// step was skipped (absent from `arguments`) or is not yet collected (a shorter
    /// probe — `mainAction` reads the outcome case with empty values).
    func value(labeled label: String, in arguments: [Argument]) -> ArgumentValue? {
        guard let index = arguments.firstIndex(where: { $0.label == label }),
              indices.contains(index) else { return nil }
        return self[index]
    }

    /// The committed text for the labeled step, or `nil` when it is absent, of a
    /// different kind, or not yet collected. An empty string is a real value — an
    /// optional text step committed empty — which `nonEmptyText` maps to "no field".
    func text(labeled label: String, in arguments: [Argument]) -> String? {
        guard case .text(let s)? = value(labeled: label, in: arguments) else { return nil }
        return s
    }

    /// The committed text for the labeled step with an **empty commit treated as
    /// absent** (issue #145) — what an optional text step (notes, location) maps to
    /// "no field", so the draft carries `nil` rather than an empty string.
    func nonEmptyText(labeled label: String, in arguments: [Argument]) -> String? {
        let value = text(labeled: label, in: arguments)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// The chosen option id for the labeled choice step, or `nil` when it is absent.
    func choiceID(labeled label: String, in arguments: [Argument]) -> String? {
        guard case .choice(let option)? = value(labeled: label, in: arguments) else { return nil }
        return option.id
    }

    /// The picked date and whether it included a time for the labeled date step, or
    /// `nil` when it is absent.
    func date(labeled label: String, in arguments: [Argument]) -> (date: Date, hasTime: Bool)? {
        guard case .date(let date, let hasTime)? = value(labeled: label, in: arguments) else { return nil }
        return (date, hasTime)
    }
}
