import SwiftUI
import UIKit
import QuickieCore
import QuickieStoreKit

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
                PastePermissionHint()
            }

            // The Providers section (CONTEXT.md → Settings; ADR 0019): one
            // navigation row per Provider, each pushing the *same*
            // `ManagementPage.settings(panel:)` destination its typed Settings
            // command row deeplinks to — value-based links onto the launcher's
            // stack, so the two routes share one page by construction. New
            // Event's former per-Action panel lives on as the Events row.
            Section {
                ForEach(ProviderID.topLevelProviders, id: \.rawValue) { provider in
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

/// The **Paste permission hint** (CONTEXT.md → Paste permission hint; issue #91):
/// the footer under the Settings app-level section telling the user how to stop
/// the iOS paste-permission alert for good, over a tappable **Open iOS Settings**
/// deeplink into Quickie's page in the Settings app (where the *Paste from Other
/// Apps* row lives — the user still flips it to **Allow** themselves; the hint
/// only shortens the trip). It replaced the footer's former toggle descriptions,
/// which restated what the self-describing toggles already said.
///
/// Passive and always present — never a popup, banner, or one-time dismissal
/// state (an information popup would fight a popup annoyance with another popup) —
/// and necessarily **blind**: iOS exposes no API to read the *Paste from Other
/// Apps* state, so the hint cannot condition on whether it is still needed. The
/// deeplink reuses the standard open-settings URL the quick-capture denied
/// affordance already uses (`UIApplication.openSettingsURLString`).
private struct PastePermissionHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        // The link is styled to read as a continuation of the hint, not a
        // separate control: same footnote size as the footer text, a shade
        // darker grey (not the accent tint a default Form button would take —
        // hence `.plain`), and a small trailing chevron cueing that the tap
        // leaves Quickie for the iOS Settings app.
        VStack(alignment: .leading, spacing: 3) {
            Text("To paste without iOS asking each time, set Paste from Other Apps to Allow in iOS Settings.")
                .accessibilityIdentifier("settings-paste-hint")

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 2) {
                    Text("Open iOS Settings")
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                .font(.footnote)
                .foregroundStyle(Color.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-open-ios-settings")
            .accessibilityLabel("Open iOS Settings")
        }
    }
}
