import Foundation

/// The **type** a Custom Action's slot carries (CONTEXT.md → Custom Action; ADR
/// 0021, issue #96), chosen per-argument in the editor and stored in the sidecar
/// config *beside* the URL — never inside the `{name}` token, which stays plain so
/// the grammar never grows. `text` is the default; `number` raises the numeric
/// keyboard variant, `date` the in-place picker, and `choice` the fuzzy option list.
public enum ArgumentType: String, Equatable, Sendable, CaseIterable {
    case text
    case number
    case date
    case choice
}

/// The per-slot **config** carried beside a Custom Action's URL (ADR 0021, issue
/// #96): everything about one `{name}` slot that isn't its token — its `type`, a
/// `choice`'s inline `options`, and a `date`'s optional output-format overrides.
/// Keyed by token name in the definition so a reorder leaves it untouched, and
/// dropped hard when its token leaves the URL (no stashing).
public struct ArgumentSpec: Equatable, Sendable {
    /// The slot's argument type — what input method the breadcrumb morphs to.
    public var type: ArgumentType
    /// A `choice` slot's options exactly as the user entered them (id = label; the
    /// chosen label is what fills the slot). Blank entries are ignored — see
    /// `effectiveOptions`.
    public var options: [String]
    /// Custom output format for a **date-only** picked value (no time), overriding
    /// the `yyyy-MM-dd` ISO default; `nil` keeps the default.
    public var dateOnlyFormat: String?
    /// Custom output format for a **timed** picked value, overriding the
    /// `yyyy-MM-dd'T'HH:mm` ISO default (e.g. Things' `yyyy-MM-dd@HH:mm`); `nil`
    /// keeps the default.
    public var timedFormat: String?

    public init(
        type: ArgumentType = .text,
        options: [String] = [],
        dateOnlyFormat: String? = nil,
        timedFormat: String? = nil
    ) {
        self.type = type
        self.options = options
        self.dateOnlyFormat = dateOnlyFormat
        self.timedFormat = timedFormat
    }

    /// The ISO default output formats a `date` slot serializes to when the editor
    /// leaves the overrides blank (issue #96): date-only when the picked value has
    /// no time, timed when it does.
    public static let defaultDateOnlyFormat = "yyyy-MM-dd"
    public static let defaultTimedFormat = "yyyy-MM-dd'T'HH:mm"

    /// The choice options that actually count — non-blank after trimming — mapped to
    /// `ChoiceOption`s whose `id` equals their `label` (the label is what fills the
    /// slot). Save is gated on this being non-empty for every choice slot.
    public var effectiveOptions: [ChoiceOption] {
        options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ChoiceOption(id: $0, label: $0) }
    }

    /// The output format a picked date serializes with, branched on whether the user
    /// included a time: the matching override when set, else the ISO default.
    public func dateFormat(hasTime: Bool) -> String {
        if hasTime { return timedFormat ?? Self.defaultTimedFormat }
        return dateOnlyFormat ?? Self.defaultDateOnlyFormat
    }
}
