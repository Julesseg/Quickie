import SwiftUI
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The **Custom Actions** Management page (CONTEXT.md → Custom Action, Management
/// page; ADR 0019/0021, issue #94): the authoring surface where a URL-template
/// Action is created, edited, enabled/disabled, and deleted — the same unified shape
/// every provider has. Options lead with the provider-level Enabled toggle; the
/// actions list follows, each row a stored Custom Action with a per-row enable/disable
/// toggle, swipe-to-delete, tap-to-edit, and an Add button. Reached by typing "Custom
/// Actions" or from the Settings Providers list. The Fallbacks page stays the
/// ordering/disable surface for the fallback-flagged ones; here every Custom Action
/// appears, fallback-flagged or not.
struct CustomActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredCustomAction.createdAt) private var customActions: [StoredCustomAction]

    /// The instance-level Disabled state (issue #68): each row's toggle reversibly
    /// hides that one Custom Action from results/Recents/Favorites.
    let enablement: EnablementStore

    @State private var editorTarget: EditorTarget?

    private enum EditorTarget: Identifiable {
        case new
        case edit(StoredCustomAction)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let action): return "edit-\(action.id)"
            }
        }
    }

    // Pushed onto the launcher's navigation stack — the back chevron and edge-swipe
    // handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019): Options lead, the stored Custom
            // Actions follow.
            ProviderOptionsSection(provider: .customActions)

            Section {
                if customActions.isEmpty {
                    Text("No Custom Actions yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(customActions) { action in
                    CustomActionRow(
                        action: action,
                        isDisabled: enablement.isDisabled(action.id),
                        onToggleDisabled: { enablement.toggleDisabled(action.id) },
                        onEdit: { editorTarget = .edit(action) }
                    )
                    .swipeActions(edge: .trailing) {
                        // Explicit Delete keeps the destructive full-swipe (the same
                        // action `.onDelete` gives in edit mode), and Duplicate rides
                        // alongside it — a fast way to fork a near-identical template.
                        Button(role: .destructive) {
                            modelContext.delete(action)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            duplicate(action)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.indigo)
                        .accessibilityIdentifier("duplicate-custom-action.\(action.id)")
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("Custom Actions")
            } footer: {
                Text("A Custom Action opens a URL template, filling its {slots} through the breadcrumb. Turn one into a fallback in its editor. Disable one to hide it without deleting it.")
            }
        }
        .navigationTitle("Custom Actions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("add-custom-action")
                .accessibilityLabel("Add Custom Action")
            }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                CustomActionEditorView(
                    definition: CustomActionDefinition(name: "", template: ""),
                    isNew: true
                ) { def in
                    modelContext.insert(StoredCustomAction.make(from: def))
                }
            case .edit(let action):
                CustomActionEditorView(definition: action.definition, isNew: false) { def in
                    action.apply(def)
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customActions[index])
        }
    }

    /// Inserts a copy of `action` — same template, type specs, fill order, and
    /// fallback flag, under a fresh identity (so pins/frecency don't alias) and a
    /// distinct " copy" title. A fast fork for authoring a near-identical variant
    /// (the PRD's "Things Todo" vs "Things Todo → Inbox").
    private func duplicate(_ action: StoredCustomAction) {
        var def = action.definition
        def.name = duplicateName(for: def.name)
        modelContext.insert(StoredCustomAction.make(from: def))
    }

    /// A distinct title for a duplicate — the original with a " copy" suffix, numbered
    /// if that is already taken — so the list never shows two identical names.
    private func duplicateName(for name: String) -> String {
        let base = "\(name) copy"
        let existing = Set(customActions.map(\.title))
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }
}

/// One row in the Custom Actions list: name, its URL template, a per-row
/// enable/disable toggle (issue #68), and a tap into the editor — the same row shape
/// as the Quicklinks and Fallbacks pages.
private struct CustomActionRow: View {
    let action: StoredCustomAction
    let isDisabled: Bool
    let onToggleDisabled: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                Text(action.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                .labelsHidden()
                .accessibilityIdentifier("custom-action-enabled.\(action.id)")
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}
