import SwiftUI
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The **Custom Actions** Management page (CONTEXT.md → Custom Action, Management
/// page; ADR 0019/0021/0045): the authoring surface where a URL-template Action is
/// created, edited, enabled/disabled, and deleted. It also owns the cross-provider
/// Fallback list: its options gate the Shelf and bottom region, then the three ladder
/// sections place every fallback-eligible Custom Action exactly once. The remaining
/// static and non-text-first Custom Actions appear under Other actions.
struct CustomActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredCustomAction.createdAt) private var customActions: [StoredCustomAction]

    /// The instance-level Disabled state (issue #68): each row's toggle reversibly
    /// hides that one Custom Action from results/Recents/Favorites.
    let store: FallbacksStore
    let enablement: EnablementStore
    let eligible: [Action]

    @State private var editorTarget: EditorTarget?
    @State private var pendingEditorTarget: EditorTarget?

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

    /// A fallback-eligible Custom Action belongs to its resolved ladder section, not
    /// a duplicate authoring row. This leaves only static links and non-text-first
    /// templates in Other actions (ADR 0045).
    private var otherActions: [StoredCustomAction] {
        customActions.filter { $0.definition.makeAction(id: $0.id)?.isFallbackEligible != true }
    }

    // Pushed onto the launcher's navigation stack — the back chevron and edge-swipe
    // handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019): Options lead. The Fallbacks toggle
            // is declared in Core directly below Enabled, with no footer.
            ProviderOptionsSection(provider: .customActions)

            // The Catalog's single entry point (CONTEXT.md → Catalog; ADR 0028;
            // issue #143) — a navigation row in the options section, the
            // Sync-Shortcut precedent.
            Section {
                NavigationLink {
                    CatalogView()
                } label: {
                    Label("Browse catalog", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("browse-catalog")
            }

            // The Custom Actions page owns this cross-provider ordering surface. Its
            // guests (Shortcuts and built-in captures) live only in this ladder.
            FallbackListSections(
                store: store,
                enablement: enablement,
                eligible: eligible,
                onSelect: { action in
                    guard action.kind == .customAction,
                          let stored = customActions.first(where: { $0.id == action.id })
                    else { return }
                    editorTarget = .edit(stored)
                }
            )
                // The fallback sections are permanently editable so their ordered
                // tiers show standard reorder grips. Keep that environment local:
                // Catalog is a navigation destination, not an editable ladder.
                .environment(\.editMode, .constant(.active))

            Section {
                if otherActions.isEmpty {
                    Text("No other actions")
                        .foregroundStyle(.secondary)
                }
                ForEach(otherActions) { action in
                    CustomActionRow(
                        action: action,
                        isDisabled: enablement.isDisabled(action.id),
                        onToggleDisabled: { enablement.toggleDisabled(action.id) },
                        onEdit: { editorTarget = .edit(action) }
                    )
                }
            } header: {
                Text("Other actions")
            }
        }
        .managementColumn()
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
        .sheet(item: $editorTarget, onDismiss: reopenPendingEditor) { target in
            switch target {
            case .new:
                CustomActionEditorView(
                    definition: CustomActionDefinition(name: "", template: ""),
                    isNew: true
                ) { def in
                    modelContext.insert(StoredCustomAction.make(from: def))
                }
            case .edit(let action):
                CustomActionEditorView(
                    definition: action.definition,
                    isNew: false,
                    onSave: { def in action.apply(def) },
                    onDuplicate: { duplicateAndReopen(action) },
                    onDelete: { modelContext.delete(action) }
                )
            }
        }
    }

    /// Sheet content does not replace its item while presented. Save the copy as the
    /// next target and present it only from `onDismiss`, after the original editor has
    /// completely left the hierarchy.
    private func duplicateAndReopen(_ action: StoredCustomAction) {
        var definition = action.definition
        definition.name = CustomActionDefinition.duplicateName(
            from: definition.name,
            existingNames: Set(customActions.map(\.title))
        )
        let copy = StoredCustomAction.make(from: definition)
        modelContext.insert(copy)
        pendingEditorTarget = .edit(copy)
        editorTarget = nil
    }

    private func reopenPendingEditor() {
        guard let pendingEditorTarget else { return }
        self.pendingEditorTarget = nil
        editorTarget = pendingEditorTarget
    }
}

/// One row in the Custom Actions list: name, its URL (template or static link), a
/// per-row enable/disable toggle (issue #68), and a tap into the editor — the same row
/// shape as the Fallbacks page.
private struct CustomActionRow: View {
    let action: StoredCustomAction
    let isDisabled: Bool
    let onToggleDisabled: () -> Void
    let onEdit: () -> Void

    /// The badge's tint follows the action's shape via the shared Core rule (a slotted
    /// template is a Custom Action, a slot-less one a static link), matching the glyph
    /// the result rows render.
    private var badgeKind: ActionKind {
        CustomActionDefinition.derivedKind(forTemplate: action.urlString)
    }

    /// The chosen leading glyph, normalized to *set* vs *unset* by the same Core rule
    /// the produced Action uses — so a blank stored value shows no badge here exactly
    /// as it renders the derived glyph on the result surfaces.
    private var chosenGlyph: String? {
        CustomActionDefinition.normalizedGlyph(action.glyph)
    }

    /// The chosen **Action color** (issue #243), resolved from the stored token by the
    /// same tolerant Core rule every other surface uses — so an unknown token shows the
    /// kind's tint here exactly as it does on a result row.
    private var chosenColor: ActionColor? {
        ActionColor(token: action.colorToken)
    }

    var body: some View {
        HStack(spacing: 12) {
            // The action's customizations appear as a leading badge on the
            // management-page row (CONTEXT.md → Custom Action, Action color; issues
            // #163, #243) — the same badge, tint, and weight the result rows wear. Shown
            // when **either** a symbol or a colour is set, since either alone makes the
            // badge say something the plain row doesn't; with neither, the row reads
            // exactly as before. A colour-only action still needs a symbol to sit on, so
            // the badge falls back to the kind-derived glyph.
            if chosenGlyph != nil || chosenColor != nil {
                ProviderBadge(kind: badgeKind, symbol: chosenGlyph, color: chosenColor)
            }
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
