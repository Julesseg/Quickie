import SwiftUI
import QuickieCore

/// The **System** umbrella provider's Management page (CONTEXT.md → System
/// provider; ADR 0029; issue #144). It groups Quickie's OS-integration actions:
///
/// - An **Options** section — rendered generically from `.system`'s declared
///   schema — leading with the **cascading** Enabled toggle (off short-circuits
///   Reminders, Events, and the two built-ins below, while their own toggles keep
///   working underneath) over two navigation rows into the unchanged Reminders and
///   Events pages (the schema's `link` kind).
/// - An **actions** section listing the permanent, **disable-only** built-in
///   Open iOS Settings. It carries the same instance enable/disable toggle its
///   result row obeys and is not deletable (no swipe-to-delete), like Save for
///   later and New Snippet. (App Store Search is a default-seeded Custom Action,
///   not a System built-in — issue #144 — so it lives on the Custom Actions page.)
///
/// Reached as the typed "System" command row or from the Settings Providers list,
/// and pushed onto the launcher's navigation stack — no own stack or Done button.
struct SystemView: View {
    /// The instance-level Disabled state (issue #68): each built-in's toggle
    /// reversibly hides that action from every launcher surface.
    let enablement: EnablementStore

    /// The permanent System built-ins, in page order. The same factories the engine
    /// indexes under `.system`, so the page and the results can never drift.
    private var builtIns: [Action] { [.openIOSSettings()] }

    var body: some View {
        List {
            // Options: Enabled (cascading) + the Reminders/Events link rows.
            ProviderOptionsSection(provider: .system)

            Section {
                ForEach(builtIns) { action in
                    SystemActionRow(
                        action: action,
                        isDisabled: enablement.isDisabled(action.id),
                        onToggleDisabled: { enablement.toggleDisabled(action.id) }
                    )
                }
                // No `.onDelete`: these are permanent built-ins — disable-only,
                // never deletable (CONTEXT.md → Management page).
            } header: {
                Text("Actions")
            } footer: {
                Text("Built-in actions. Disable one to hide it from results without removing it — they can't be deleted.")
            }
        }
        .navigationTitle("System")
    }
}

/// One System built-in row: the action's title with a short caption and its
/// instance enable/disable toggle. No tap target and no delete affordance — a
/// built-in is configured only by its toggle.
private struct SystemActionRow: View {
    let action: Action
    let isDisabled: Bool
    let onToggleDisabled: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                .labelsHidden()
                .accessibilityIdentifier("system-action-enabled.\(action.id)")
        }
    }

    /// A one-line description of what the built-in does.
    private var caption: String? {
        switch action.id {
        case Action.openIOSSettingsID: return "Open Quickie's page in the iOS Settings app"
        default: return nil
        }
    }
}
