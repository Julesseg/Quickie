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

/// The Settings page (CONTEXT.md → Settings): a full-screen management page holding
/// **Appearance** (Light / Dark / System, defaulting to System, applied app-wide)
/// and an **Actions** section — a row per configurable capture Action that pushes
/// its own per-Action panel (New Event today; issue #38). Reached by typing to
/// surface the "Settings" command row, not from chrome; it is pushed onto the
/// launcher's navigation stack, so it slides in from the right and its panels push
/// onto the same stack, dismissing via the back chevron or the system edge-swipe.
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
