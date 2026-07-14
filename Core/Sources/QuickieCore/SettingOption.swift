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
/// app resolves at render time (the EventKit calendars / reminder lists). Both may
/// lead with `leadingOptions` — synthetic rows shown *before* the option set, each
/// mapping to a reserved stored value rather than a live option: the capture pickers
/// lead with "Ask each time" (the empty sentinel → `.ask`) and "Default calendar" /
/// "Default list" (the system-default sentinel → `.fixed(id: nil)`), so both routings
/// the old settings expressed survive.
public struct ChoiceSetting: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case `static`(options: [ChoiceOption])
        case dynamic(DynamicOptionSource)
    }

    public let source: Source
    /// Synthetic rows shown before the option set, each with the stored value it
    /// selects — the routing sentinels above. Empty for a plain pick.
    public let leadingOptions: [ChoiceOption]
    /// The stored value when nothing specific is chosen (empty = "Ask each time").
    public let defaultValue: String

    public init(source: Source, leadingOptions: [ChoiceOption] = [], defaultValue: String = "") {
        self.source = source
        self.leadingOptions = leadingOptions
        self.defaultValue = defaultValue
    }
}

/// Reserved dynamic-choice stored values (issue #69) that name a *routing* rather
/// than a live option. Empty string is "Ask each time" (`.ask`); `systemDefault` is
/// "save silently to the system default" (`.fixed(id: nil)`) — the state the old
/// ask-off Event/Reminder setting expressed, which the app's one-time migration
/// seeds so an upgrade never silently flips it back to asking. A reserved token that
/// can't collide with an EventKit calendar/list identifier.
public enum SettingsChoice {
    public static let systemDefault = "__quickie_system_default__"

    /// The value to seed a dynamic-choice key from the retired ask/default-id pair
    /// (issue #69) when migrating an install off the old Event/Reminder settings. The
    /// old routing was `ask ? .ask : .fixed(id: defaultID or system default)`, so:
    /// ask-on → "" ("Ask each time"); ask-off → the set default id, or the
    /// system-default sentinel when none was set (the only reachable ask-off state,
    /// since the old UI never exposed a default-id picker). Keeps an upgrade from
    /// silently flipping a "save silently" capture back to asking.
    public static func migratedSelection(ask: Bool, defaultID: String) -> String {
        if ask { return "" }
        return defaultID.isEmpty ? systemDefault : defaultID
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
    /// The New Event enabled, ordered **step plan** (issue #145 follow-up) — the raw
    /// step ids the reorderable double-list persists.
    public static let eventSteps = "event.steps"
    /// The New Reminder due-date toggle (retired as a schema option; issue #145
    /// follow-up). Kept only so the step-plan migration can read the old value.
    public static let reminderAskDate = "reminder.askDate"
    /// The New Reminder enabled, ordered **step plan** (issue #145 follow-up) — the raw
    /// step ids the reorderable double-list persists.
    public static let reminderSteps = "reminder.steps"
    /// The New Reminder default-list choice: the target when the List step is off.
    public static let reminderList = "reminder.list"
    /// The Computed provider's five per-type toggles (ADR 0032), all default-on. The
    /// keys keep the `calculator.` prefix because the persisted provider identity
    /// stays `.calculator` — renaming would re-key stored state. Math and Unit
    /// conversion gate the Calculator rows; URLs, Phone numbers, and Email addresses
    /// gate the Detected result rows.
    public static let calculatorMath = "calculator.math"
    public static let calculatorUnitConversion = "calculator.unitConversion"
    public static let calculatorURL = "calculator.url"
    public static let calculatorPhone = "calculator.phone"
    public static let calculatorEmail = "calculator.email"
    /// The File Search inline-result cap stepper.
    public static let fileSearchInlineCap = "file-search.inlineCap"
    /// The Pile's Pending-query auto-save toggle (issue #152): on saves
    /// unresolved input to the Pile after the fixed 30-second window; off is the
    /// old behavior exactly — state preserved indefinitely, nothing saved.
    public static let pileAutoSave = "pile.autoSave"
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
            footer: enabledFooter,
            kind: .enabled
        )
    }

    /// The Enabled toggle's footer. The umbrella provider (System, ADR 0029)
    /// describes its **cascade** — off silences its member kinds too — while every
    /// other provider gets the plain reversible-hide copy.
    private var enabledFooter: String {
        switch self {
        case .system:
            return "Off hides Reminders, Events, and Open iOS Settings from results, Recents, and Favorites until you turn it back on. Reminders and Events keep their own settings underneath, so turning System back on restores them. You can always reach this page by typing its name."
        default:
            return "Off hides \(displayName) from results, Recents, and Favorites until you turn it back on. Its data is kept, and you can always reach this page by typing its name."
        }
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
                    title: "Default calendar",
                    footer: "Where an event is saved when the Calendar step is off. Turn the Calendar step on below to pick per event instead.",
                    kind: .choice(ChoiceSetting(
                        source: .dynamic(.eventCalendars),
                        leadingOptions: [
                            ChoiceOption(id: "", label: "Default calendar"),
                        ]
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
                    key: SettingsKey.reminderList,
                    title: "Default list",
                    footer: "Where a reminder is saved when the List step is off. Turn the List step on below to pick per reminder instead.",
                    kind: .choice(ChoiceSetting(
                        source: .dynamic(.reminderLists),
                        leadingOptions: [
                            ChoiceOption(id: "", label: "Default list"),
                        ]
                    ))
                ),
            ]
        case .system:
            // The umbrella declares no own options beyond Enabled (ADR 0029): its
            // member navigation rows (Reminders, Events) and its own built-in (Open
            // iOS Settings) all render together in the page's Actions section, not
            // as options. Reminders and Events stay full providers in their own
            // right — System groups them, it does not merge them.
            return []
        case .pile:
            return [
                SettingOption(
                    key: SettingsKey.pileAutoSave,
                    title: "Save unfinished input",
                    footer: "Leave the app with unfinished text in the input and it's saved here after 30 seconds — come back sooner and it's still where you left it. Off keeps whatever you typed in place indefinitely.",
                    kind: .toggle(default: true)
                ),
            ]
        case .calculator:
            // The Computed provider's five per-type toggles (ADR 0032), all default-on,
            // beneath the provider-level Enabled switch. Each suppresses exactly its
            // rows; the three detection toggles off restore the pre-detection Calculator.
            return [
                SettingOption(
                    key: SettingsKey.calculatorMath,
                    title: "Math",
                    footer: "On answers arithmetic (e.g. \"23 * 7\"). Off keeps the row from appearing for a math expression.",
                    kind: .toggle(default: true)
                ),
                SettingOption(
                    key: SettingsKey.calculatorUnitConversion,
                    title: "Unit conversion",
                    footer: "On also answers offline unit conversions (e.g. \"10 km in mi\"). Off keeps Computed to arithmetic only.",
                    kind: .toggle(default: true)
                ),
                SettingOption(
                    key: SettingsKey.calculatorURL,
                    title: "URLs",
                    footer: "On turns a typed link or bare domain (e.g. \"apple.com\") into an Open row. Off leaves it to the web-search fallback.",
                    kind: .toggle(default: true)
                ),
                SettingOption(
                    key: SettingsKey.calculatorPhone,
                    title: "Phone numbers",
                    footer: "On turns a typed phone number (e.g. \"555-1212\") into Message and Call rows. Off suppresses them.",
                    kind: .toggle(default: true)
                ),
                SettingOption(
                    key: SettingsKey.calculatorEmail,
                    title: "Email addresses",
                    footer: "On turns a typed email address (e.g. \"me@work.com\") into an Email row. Off suppresses it.",
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
