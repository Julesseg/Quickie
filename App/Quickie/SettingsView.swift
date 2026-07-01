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

/// The Settings page (CONTEXT.md → Settings): a full-screen management page holding
/// the **app-level** section — **Appearance** (Light / Dark / System, defaulting to
/// System, applied app-wide), the **Clipboard prefill** toggle, and the **Show
/// Recents** toggle (issue #65) — and an **Actions** section — a row per
/// configurable capture Action that pushes its own per-Action panel (New Event
/// today; issue #38). Reached by typing to surface the "Settings" command row, not
/// from chrome; it is pushed onto the launcher's navigation stack, so it slides in
/// from the right and its panels push onto the same stack, dismissing via the back
/// chevron or the system edge-swipe.
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

            // Per-Action settings (CONTEXT.md → Settings, Quick capture): each
            // configurable capture Action gets a row that pushes its own panel onto
            // the launcher's stack. New Event is the first (issue #38).
            Section {
                NavigationLink {
                    EventSettingsView()
                } label: {
                    Label("New Event", systemImage: "calendar")
                }
                .accessibilityIdentifier("settings-action-new-event")
            } header: {
                Text("Actions")
            }
        }
        .navigationTitle("Settings")
    }
}
