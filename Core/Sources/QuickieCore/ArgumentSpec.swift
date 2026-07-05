import Foundation

/// The **type** a Custom Action's slot carries (CONTEXT.md → Custom Action; ADR
/// 0021, issue #96), chosen per-argument in the editor and stored in the sidecar
/// config *beside* the URL — never inside the `{name}` token, which stays plain so
/// the grammar never grows. `text` is the default; `number` raises the numeric
/// keyboard variant, `date` the in-place picker, and `choice` the fuzzy option list.
public enum ArgumentType: String, Equatable, Sendable, CaseIterable, Codable {
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
public struct ArgumentSpec: Equatable, Sendable, Codable {
    /// The slot's argument type — what input method the breadcrumb morphs to.
    public var type: ArgumentType
    /// A `choice` slot's options exactly as the user entered them (id = label; the
    /// chosen label is what fills the slot). Blank entries are ignored — see
    /// `effectiveOptions`.
    public var options: [String]
    /// A **single** custom output format for a `date` slot (issue #96). Its *meaning*
    /// decides whether the slot collects a date or a date-and-time: a format carrying
    /// time tokens (`H`, `h`, `m`, `s`, …) makes it a datetime and the picker offers a
    /// time; a format without them keeps it date-only — there is no separate toggle to
    /// switch between the two. `nil`/blank uses the ISO `yyyy-MM-dd` date-only default.
    public var dateFormat: String?

    public init(
        type: ArgumentType = .text,
        options: [String] = [],
        dateFormat: String? = nil
    ) {
        self.type = type
        self.options = options
        self.dateFormat = dateFormat
    }

    /// The ISO default output formats a `date` slot serializes to when the editor
    /// leaves the format blank (issue #96): date-only, or timed for a format that
    /// carries a time (the picked value's time then survives into the URL).
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

    /// The custom format trimmed of leading/trailing whitespace, or `nil` when blank —
    /// the editor keeps the raw text for typing fidelity (a format may carry *internal*
    /// spaces, e.g. `MMM d yyyy`), but stray edge whitespace must never reach
    /// `DateFormatter` and leak a literal space into the filled URL.
    var trimmedDateFormat: String? {
        guard let trimmed = dateFormat?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Whether this date slot collects a **time**, derived from the custom format's
    /// meaning (a blank format is date-only). The editor never asks — the format is
    /// the single source, and the breadcrumb's picker is restricted to match.
    public var dateIncludesTime: Bool {
        guard let format = trimmedDateFormat else { return false }
        return Self.formatIncludesTime(format)
    }

    /// The output format a picked date serializes with: the custom format when set,
    /// else the ISO default (timed vs date-only per `hasTime`).
    public func outputFormat(hasTime: Bool) -> String {
        if let format = trimmedDateFormat { return format }
        return hasTime ? Self.defaultTimedFormat : Self.defaultDateOnlyFormat
    }

    /// Whether a `DateFormatter` pattern carries any **time** component, ignoring
    /// single-quoted literals — so the `'T'` in `yyyy-MM-dd'T'HH:mm` is a literal, not a
    /// time token, while its `HH:mm` counts. Case-sensitive: lowercase `m` is minute
    /// (uppercase `M` is month), so a bare `dd/MM/yyyy` is date-only.
    static func formatIncludesTime(_ format: String) -> Bool {
        var unquoted = ""
        var inQuote = false
        for character in format {
            if character == "'" { inQuote.toggle(); continue }
            if !inQuote { unquoted.append(character) }
        }
        let timeTokens: Set<Character> = ["H", "h", "m", "s", "S", "a", "A", "k", "K"]
        return unquoted.contains(where: timeTokens.contains)
    }
}
