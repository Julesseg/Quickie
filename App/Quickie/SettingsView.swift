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
/// "Settings" command row, not from chrome; it presents full-screen with its own
/// Done affordance.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// The persisted appearance preference, stored by its `Appearance` raw value
    /// and read back through the Core type (System → no forced scheme). Shared
    /// app-wide via `@AppStorage`, so changing it here updates the whole app.
    @AppStorage("appearance") private var appearanceRaw = Appearance.default.rawValue

    private var appearance: Binding<Appearance> {
        Binding(
            get: { Appearance(stored: appearanceRaw) },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: appearance) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("appearance-picker")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Applies to the whole app. System follows your device.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
