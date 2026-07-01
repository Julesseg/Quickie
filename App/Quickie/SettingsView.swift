import SwiftUI
import QuickieCore

extension Appearance {
    /// The SwiftUI `ColorScheme` this preference forces, or `nil` for **System**
    /// (follow the device). The App applies it app-wide via `preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The top-level Settings hub (CONTEXT.md → Settings; ADR 0019, issue #66): an
/// **app-level** section — Appearance today; the #65 toggles join it — over a
/// **Providers** section, one navigation row per Provider. The rows are
/// navigation only: each pushes that provider's unified Management page, the
/// same destination its typed Settings command row deeplinks to, so the hub and
/// the deeplink can never diverge. Reached by typing to surface the "Settings"
/// command row, not from chrome; it is pushed onto the launcher's navigation
/// stack, so it slides in from the right and its pages push onto the same
/// stack, dismissing via the back chevron or the system edge-swipe.
struct SettingsView: View {
    /// The persisted appearance preference, stored by its `Appearance` raw value
    /// and read back through the Core type (System → no forced scheme). Shared
    /// app-wide via `@AppStorage`, so changing it here updates the whole app.
    @AppStorage("appearance") private var appearanceRaw = Appearance.default.rawValue

    private var selected: Appearance { Appearance(stored: appearanceRaw) }

    var body: some View {
        Form {
            Section {
                // A plain checkmark list rather than an inline `Picker`, whose
                // own label would repeat the section header as a dead first row.
                ForEach(Appearance.allCases, id: \.rawValue) { option in
                    Button {
                        appearanceRaw = option.rawValue
                    } label: {
                        HStack {
                            Text(option.rawValue.capitalized)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option == selected {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance-\(option.rawValue)")
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applies to the whole app. System follows your device.")
            }

            // The Providers section (CONTEXT.md → Settings; ADR 0019): one
            // navigation row per Provider, each pushing the *same*
            // `ManagementPage.settings(panel:)` destination its typed Settings
            // command row deeplinks to — value-based links onto the launcher's
            // stack, so the two routes share one page by construction. New
            // Event's former per-Action panel lives on as the Events row.
            Section {
                ForEach(ProviderID.allCases, id: \.rawValue) { provider in
                    NavigationLink(value: ManagementPage.settings(panel: provider)) {
                        Label(provider.displayName, systemImage: provider.symbol)
                    }
                    .accessibilityIdentifier("settings-provider-\(provider.rawValue)")
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Each provider's settings and content live on its own page. You can also get there by typing its name.")
            }
        }
        .navigationTitle("Settings")
    }
}
