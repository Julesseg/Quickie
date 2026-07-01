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

/// The app-level Settings preferences beyond Appearance (CONTEXT.md → Settings;
/// issue #65): the **Clipboard prefill** and **Show Recents** on/off toggles,
/// both defaulting to on. Persisted in the shared App Group defaults
/// (`AppGroup.defaults`) so they survive launches and any future extension reads
/// the same source of truth. The `@AppStorage` defaults here and in `RootView`
/// must agree so the first read before any write does too.
struct AppSettings {
    static let clipboardPrefillKey = "app.clipboardPrefill"
    static let showRecentsKey = "app.showRecents"

    /// Clears both toggles back to their defaults. Honors the same UI-test reset
    /// flag as SignalsStore (see `QuickieApp`): a test asking for a clean
    /// launcher also gets clean app-level settings.
    static func reset(in defaults: UserDefaults) {
        defaults.removeObject(forKey: clipboardPrefillKey)
        defaults.removeObject(forKey: showRecentsKey)
    }
}

/// The top-level Settings hub (CONTEXT.md → Settings; ADR 0019, issue #66): an
/// **app-level** section — Appearance plus the Clipboard prefill and Show
/// Recents toggles (issue #65) — over a **Providers** section, one navigation
/// row per Provider. The rows are navigation only: each pushes that provider's
/// unified Management page, the same destination its typed Settings command row
/// deeplinks to, so the hub and the deeplink can never diverge. Reached by
/// typing to surface the "Settings" command row, not from chrome; it is pushed
/// onto the launcher's navigation stack, so it slides in from the right and its
/// pages push onto the same stack, dismissing via the back chevron or the
/// system edge-swipe.
struct SettingsView: View {
    /// The persisted appearance preference, stored by its `Appearance` raw value
    /// and read back through the Core type (System → no forced scheme). Shared
    /// app-wide via `@AppStorage`, so changing it here updates the whole app.
    @AppStorage("appearance") private var appearanceRaw = Appearance.default.rawValue

    /// The app-level **Clipboard prefill** toggle (issue #65): off suppresses the
    /// launch-time paste chip on Home. Content is only ever read behind a user
    /// tap, so the toggle gates the *offer*, not any ambient read.
    @AppStorage(AppSettings.clipboardPrefillKey, store: AppGroup.defaults)
    private var clipboardPrefillEnabled = true

    /// The app-level **Show Recents** toggle (issue #65): off hides the Frecency
    /// "Recent" list on Home. The signals keep recording; only the surface hides.
    @AppStorage(AppSettings.showRecentsKey, store: AppGroup.defaults)
    private var showRecents = true

    var body: some View {
        Form {
            // The app-level section (CONTEXT.md → Settings): Appearance plus the
            // two Home-surface toggles, one tier above the per-Action panels.
            // Appearance is a labeled menu `Picker` now that it shares a section —
            // the old checkmark list existed only because a lone Picker's label
            // would have repeated its section header as a dead first row.
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(Appearance.allCases, id: \.rawValue) { option in
                        Text(option.rawValue.capitalized)
                            .tag(option.rawValue)
                            .accessibilityIdentifier("appearance-\(option.rawValue)")
                    }
                }
                .accessibilityIdentifier("appearance-picker")

                Toggle("Clipboard prefill", isOn: $clipboardPrefillEnabled)
                    .accessibilityIdentifier("settings-clipboard-prefill")

                Toggle("Show Recents", isOn: $showRecents)
                    .accessibilityIdentifier("settings-show-recents")
            } header: {
                Text("App")
            } footer: {
                Text("Appearance applies to the whole app; System follows your device. Clipboard prefill offers to paste what you copied; Show Recents lists recently used actions on Home.")
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
