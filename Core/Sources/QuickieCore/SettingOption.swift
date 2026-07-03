import Foundation

/// One typed entry in a Provider's declared Options schema (ADR 0020; issue #69).
/// Each Provider declares its Options as an ordered `[SettingOption]` in Core, and
/// the app's generic renderer draws any schema without a bespoke view per provider
/// — panel structure, defaults, and enablement live here, covered by `swift test`.
///
/// An option carries the persistence/accessibility `key`, the user-facing `title`,
/// an optional explanatory `footer`, and a `kind` holding the type-specific data.
/// The rule is **schema unless no case fits** (ADR 0020): the `bespoke` escape hatch
/// is the deliberate pressure valve, kept unused so it never becomes a dumping ground.
public struct SettingOption: Identifiable, Equatable, Sendable {
    /// The persisted identity — the `@AppStorage` key the app reads/writes and the
    /// accessibility identifier the renderer stamps. Stable: renaming a title must
    /// never re-key stored state. The Enabled toggle is the one exception (it keys
    /// off the provider via `ProviderEnablement`), so it uses `enabledKey`.
    public let key: String
    /// The row label shown in the Options section.
    public let title: String
    /// The section footer explaining what the option does, or `nil` for a bare row.
    public let footer: String?
    /// The type-specific payload the renderer switches on.
    public let kind: Kind

    public var id: String { key }

    public init(key: String, title: String, footer: String? = nil, kind: Kind) {
        self.key = key
        self.title = title
        self.footer = footer
        self.kind = kind
    }

    /// The reserved `key` of the provider-level Enabled toggle (issue #67), the
    /// schema's first entry for every provider. Unlike the other options it does not
    /// persist to `@AppStorage`: the renderer binds it to `ProviderEnablement`.
    public static let enabledKey = "enabled"

    /// The type-specific data behind an option — what the renderer switches on to
    /// draw the right control (ADR 0020).
    public enum Kind: Equatable, Sendable {
        /// The provider-level Enabled switch (issue #67). Bound by the renderer to
        /// `ProviderEnablement`, not `@AppStorage`; always the schema's first entry.
        case enabled
        /// An on/off switch persisted at the option's `key`, defaulting to `default`.
        case toggle(default: Bool)
        /// A single-choice picker over a fixed (`static`) or live (`dynamic`) option
        /// set — the latter fed by the app (e.g. the EventKit calendar list).
        case choice(ChoiceSetting)
        /// A bounded integer stepper (e.g. File Search's inline-result cap).
        case stepper(StepperSetting)
        /// A genuine cross-reference to another management page (ADR 0020) — not the
        /// provider's own content, which lives on the same page. A navigation row.
        case link(ManagementPage)
        /// The **bespoke sub-view escape hatch** (ADR 0020): an option no schema case
        /// can express, rendered by an app-supplied sub-view keyed by `identifier`.
        /// Deliberately unused today — the pressure valve stays schema-first.
        case bespoke(identifier: String)
    }
}

/// A single-choice option's option set and default (ADR 0020; issue #69). A `static`
/// source carries its fixed options in Core; a `dynamic` source names a live set the
/// app resolves at render time (the EventKit calendars / reminder lists), optionally
/// with a leading `placeholder` row that maps to the empty/sentinel stored value
/// (the capture pickers' "Ask each time").
public struct ChoiceSetting: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case `static`(options: [ChoiceOption])
        case dynamic(DynamicOptionSource)
    }

    public let source: Source
    /// The label of the leading row that stores the sentinel (empty) value — "Ask
    /// each time" for the capture pickers; `nil` for a plain pick with no such row.
    public let placeholder: String?
    /// The stored value when nothing specific is chosen. Empty string is the
    /// sentinel the `placeholder` row (when present) represents.
    public let defaultValue: String

    public init(source: Source, placeholder: String? = nil, defaultValue: String = "") {
        self.source = source
        self.placeholder = placeholder
        self.defaultValue = defaultValue
    }
}

/// Which live option set a `dynamic choice` draws from (ADR 0020; issue #69). Core
/// names the source; the app resolves it to `[ChoiceOption]` at render time (the
/// app-side hook the ADR calls out). Kept a small closed enum so a new dynamic
/// choice is a deliberate addition on both sides.
public enum DynamicOptionSource: String, Equatable, Sendable, CaseIterable {
    /// The user's writable EventKit calendars (the New Event target-calendar picker).
    case eventCalendars
    /// The user's modifiable EventKit reminder lists (the New Reminder list picker).
    case reminderLists
}

/// A bounded integer setting rendered as a stepper (ADR 0020; issue #69) — File
/// Search's inline-result cap is the first. Carries its inclusive `range`, `step`,
/// and `defaultValue`; `clamped` keeps a persisted or nudged value inside the range
/// so a stale or out-of-bounds store can never drive the provider past its bounds.
public struct StepperSetting: Equatable, Sendable {
    public let range: ClosedRange<Int>
    public let step: Int
    public let defaultValue: Int

    public init(range: ClosedRange<Int>, step: Int = 1, defaultValue: Int) {
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
    }

    /// Clamps `value` into `range` — the renderer and the provider both read through
    /// this so a stored value outside the current bounds never escapes.
    public func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The `@AppStorage` keys the schema options persist against (issue #69), owned by
/// Core so the declared schema and the app's capture settings never drift onto
/// different keys. The Enabled toggle is the one option that does *not* appear here:
/// it keys off the provider via `ProviderEnablement` (`SettingOption.enabledKey`).
public enum SettingsKey {
    /// The New Event target-calendar dynamic choice: empty = "Ask each time"
    /// (`.ask`), any other value a fixed calendar id.
    public static let eventCalendar = "event.calendar"
    /// The New Event silent-vs-editor toggle (default silent, off).
    public static let eventEditor = "event.editor"
    /// The New Reminder due-date step toggle (default on).
    public static let reminderAskDate = "reminder.askDate"
    /// The New Reminder target-list dynamic choice: empty = "Ask each time".
    public static let reminderList = "reminder.list"
    /// The Calculator unit-conversion toggle (default on).
    public static let calculatorUnitConversion = "calculator.unitConversion"
    /// The File Search inline-result cap stepper.
    public static let fileSearchInlineCap = "file-search.inlineCap"
}

public extension ProviderID {
    /// The declared **Options** schema the provider's Management page renders
    /// generically (ADR 0020; issue #69). The provider-level Enabled toggle (issue
    /// #67) is always the first entry; the provider's own options follow.
    var settingsSchema: [SettingOption] {
        [enabledOption] + ownOptions
    }

    /// The Enabled toggle every schema leads with (issue #67) — reversibly hides the
    /// whole kind while its data and configuration are retained.
    private var enabledOption: SettingOption {
        SettingOption(
            key: SettingOption.enabledKey,
            title: "Enabled",
            footer: "Off hides \(displayName) from results, Recents, and Favorites until you turn it back on. Its data is kept, and you can always reach this page by typing its name.",
            kind: .enabled
        )
    }

    /// The provider's own options beyond Enabled. Providers with no configurable
    /// options (their page is Enabled plus, for content providers, an actions list)
    /// declare none.
    private var ownOptions: [SettingOption] {
        switch self {
        case .events:
            return [
                SettingOption(
                    key: SettingsKey.eventCalendar,
                    title: "Calendar",
                    footer: "Ask each time adds a calendar step to the capture. Pick a calendar to save every event there silently.",
                    kind: .choice(ChoiceSetting(
                        source: .dynamic(.eventCalendars),
                        placeholder: "Ask each time"
                    ))
                ),
                SettingOption(
                    key: SettingsKey.eventEditor,
                    title: "Review in Calendar before saving",
                    footer: "On opens the system event editor pre-filled with what you captured — so you can set alerts, invitees, or recurrence before saving. Off saves silently.",
                    kind: .toggle(default: false)
                ),
            ]
        case .reminders:
            return [
                SettingOption(
                    key: SettingsKey.reminderAskDate,
                    title: "Ask for a due date",
                    footer: "On adds a due-date step to the capture. Off saves the reminder with no date.",
                    kind: .toggle(default: true)
                ),
                SettingOption(
                    key: SettingsKey.reminderList,
                    title: "List",
                    footer: "Ask each time adds a list step to the capture. Pick a list to save every reminder there silently.",
                    kind: .choice(ChoiceSetting(
                        source: .dynamic(.reminderLists),
                        placeholder: "Ask each time"
                    ))
                ),
            ]
        case .calculator:
            return [
                SettingOption(
                    key: SettingsKey.calculatorUnitConversion,
                    title: "Unit conversion",
                    footer: "On also answers offline unit conversions (e.g. \"10 km in mi\"). Off keeps the Calculator to arithmetic only.",
                    kind: .toggle(default: true)
                ),
            ]
        case .fileSearch:
            return [
                SettingOption(
                    key: SettingsKey.fileSearchInlineCap,
                    title: "Inline results",
                    footer: "How many file matches can appear inline while you type. The Search Files context always shows every match.",
                    kind: .stepper(StepperSetting(range: 1...10, defaultValue: 3))
                ),
            ]
        default:
            return []
        }
    }
}
