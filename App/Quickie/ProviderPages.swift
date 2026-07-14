import SwiftUI
import QuickieCore

/// The **Options** section every provider page leads with (CONTEXT.md → Management
/// page; ADR 0019/0020, issues #67 & #69), rendered **generically from the
/// provider's declared schema**. Each `SettingOption` in `provider.settingsSchema`
/// becomes one row — the provider-level Enabled toggle first (issue #67), then the
/// provider's own toggles, choices, and steppers. There is no bespoke view per
/// provider: adding an option is a Core declaration (ADR 0020), and this one
/// renderer draws it everywhere the section is embedded.
///
/// The schema owns structure, defaults, and copy; this view owns only the SwiftUI
/// controls and the persistence edges — `ProviderEnablement` for the Enabled switch,
/// `@AppStorage` for the rest, and the app-supplied live options for a dynamic
/// choice. Settings itself has no `ProviderID`, so no page can render a toggle for
/// it — non-disableable by construction.
struct ProviderOptionsSection: View {
    let provider: ProviderID

    private var schema: [SettingOption] { provider.settingsSchema }

    var body: some View {
        // Each option is its own Section so it can carry its own footer; the first
        // (the Enabled toggle) also carries the "Options" header the section leads
        // with. Later options are headerless — their control label names them.
        ForEach(schema) { option in
            Section {
                OptionRow(provider: provider, option: option)
            } header: {
                if option.id == schema.first?.id { Text("Options") }
            } footer: {
                if let footer = option.footer { Text(footer) }
            }
        }
    }
}

/// One schema row (ADR 0020; issue #69): switches on the option's `kind` to the
/// matching control. The `bespoke` escape hatch renders nothing today — it is the
/// deliberate, unused pressure valve; the rule stays schema-first.
private struct OptionRow: View {
    let provider: ProviderID
    let option: SettingOption

    var body: some View {
        switch option.kind {
        case .enabled:
            EnabledToggleRow(provider: provider)
        case .toggle(let defaultValue):
            ToggleOptionRow(key: option.key, title: option.title, defaultValue: defaultValue)
        case .choice(let choice):
            ChoiceOptionRow(key: option.key, title: option.title, choice: choice)
        case .stepper(let stepper):
            StepperOptionRow(key: option.key, title: option.title, stepper: stepper)
        case .link(let page):
            NavigationLink(value: page) { Text(option.title) }
                .accessibilityIdentifier("setting-\(option.key)")
        case .bespoke:
            // The escape hatch (ADR 0020): present in the schema type, unused today.
            EmptyView()
        }
    }
}

/// The provider-level Enabled switch (issue #67) — the one option that persists to
/// `ProviderEnablement` rather than `@AppStorage`, keyed off the provider. Keeps the
/// `provider-enabled-<id>` identifier the Settings-hub UI acceptance tests drive.
private struct EnabledToggleRow: View {
    let provider: ProviderID
    @Environment(ProviderEnablementStore.self) private var enablement

    var body: some View {
        Toggle("Enabled", isOn: Binding(
            get: { enablement.isEnabled(provider) },
            set: { enablement.setEnabled($0, for: provider) }
        ))
        .accessibilityIdentifier("provider-enabled-\(provider.rawValue)")
    }
}

/// A schema `toggle` bound to `@AppStorage` at the option's key (ADR 0020). The key
/// is a runtime value, so the store is constructed in `init` rather than via the
/// literal-key `@AppStorage` initializer.
private struct ToggleOptionRow: View {
    private let title: String
    private let key: String
    @AppStorage private var value: Bool

    init(key: String, title: String, defaultValue: Bool) {
        self.key = key
        self.title = title
        _value = AppStorage(wrappedValue: defaultValue, key)
    }

    var body: some View {
        Toggle(title, isOn: $value)
            .accessibilityIdentifier("setting-\(key)")
    }
}

/// A schema `stepper` (ADR 0020; issue #69) — File Search's inline-result cap is the
/// first. Bound to `@AppStorage` and clamped through the declared `StepperSetting` so
/// a stale or out-of-bounds store can never drive the provider past its bounds.
private struct StepperOptionRow: View {
    private let title: String
    private let key: String
    private let stepper: StepperSetting
    @AppStorage private var value: Int

    init(key: String, title: String, stepper: StepperSetting) {
        self.key = key
        self.title = title
        self.stepper = stepper
        _value = AppStorage(wrappedValue: stepper.defaultValue, key)
    }

    var body: some View {
        Stepper(value: $value, in: stepper.range, step: stepper.step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(stepper.clamped(value))")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("setting-\(key)-value")
            }
        }
        .accessibilityIdentifier("setting-\(key)")
    }
}

/// A schema `choice` (ADR 0020; issue #69): a picker over a fixed (`static`) or live
/// (`dynamic`) option set. A dynamic choice — the EventKit calendar / reminder-list
/// pickers — resolves its options from the app-supplied `DynamicSettingOptions` at
/// render time, beneath the schema's `leadingOptions` routing rows ("Ask each time"
/// storing the empty sentinel `.ask`, "Default calendar/list" the system-default one).
private struct ChoiceOptionRow: View {
    private let title: String
    private let key: String
    private let choice: ChoiceSetting
    @AppStorage private var value: String
    @Environment(DynamicSettingOptions.self) private var dynamicOptions
    @State private var liveOptions: [ChoiceOption] = []

    init(key: String, title: String, choice: ChoiceSetting) {
        self.key = key
        self.title = title
        self.choice = choice
        _value = AppStorage(wrappedValue: choice.defaultValue, key)
    }

    /// The option set the picker offers below the routing rows: static options come
    /// straight from the schema; dynamic ones from the app, loaded on appear.
    private var options: [ChoiceOption] {
        switch choice.source {
        case .static(let options): return options
        case .dynamic: return liveOptions
        }
    }

    var body: some View {
        Picker(title, selection: $value) {
            // The routing rows first (e.g. "Ask each time" → "", "Default calendar"
            // → the system-default sentinel), then the live/static option set.
            ForEach(choice.leadingOptions) { option in
                Text(option.label).tag(option.id)
            }
            ForEach(options) { option in
                Text(option.label).tag(option.id)
            }
        }
        .accessibilityIdentifier("setting-\(key)")
        .task {
            // Live options are only meaningful for a dynamic source; a static choice
            // needs no fetch. An unauthorized EventKit store yields an empty set, so
            // the picker simply offers "Ask each time" until access is granted.
            if case .dynamic(let source) = choice.source {
                liveOptions = await dynamicOptions.options(for: source)
            }
        }
    }
}

/// The unified page for a provider with **no enumerable instances** (CONTEXT.md →
/// Management page; ADR 0019): Computed, Reminders, and Events show only the
/// Options section — there is no content list to render beneath it. Content
/// providers (File Search included, whose content is its folder grants) instead
/// lead their own list pages with the same `ProviderOptionsSection`.
struct ProviderOptionsPage: View {
    let provider: ProviderID

    var body: some View {
        Form {
            ProviderOptionsSection(provider: provider)
        }
        .navigationTitle(provider.displayName)
    }
}

extension ProviderID {
    /// The SF Symbol the Settings hub's Providers list shows beside each row —
    /// the same vocabulary as the result rows' provider badges (`ActionIcons`),
    /// so a provider looks like itself on both surfaces.
    var symbol: String {
        switch self {
        case .customActions: return "bolt.horizontal"
        case .fallbacks: return "magnifyingglass"
        case .snippets: return "doc.on.clipboard"
        case .pile: return "tray.full"
        case .shortcuts: return "square.stack.3d.up"
        case .reminders: return "checklist"
        case .events: return "calendar"
        case .system: return "gearshape.2"
        case .calculator: return "function"
        case .fileSearch: return "doc.text.magnifyingglass"
        }
    }
}
