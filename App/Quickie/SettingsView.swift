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

/// The Settings page (CONTEXT.md → Settings): a full-screen management page that
/// holds a single control — **Appearance** (Light / Dark / System, defaulting to
/// System), persisted and applied app-wide. Reached by typing to surface the
/// "Settings" command row, not from chrome; it is pushed onto the launcher's
/// navigation stack, so it slides in from the right and dismisses via the back
/// chevron or the system edge-swipe.
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
        }
        .navigationTitle("Settings")
    }
}
