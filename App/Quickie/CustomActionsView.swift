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
    /// The guest-provider stores let a row open the page that owns it without
    /// introducing a second copy of the fallback list in that provider.
    let shortcuts: ShortcutsStore
    let reminderSteps: CaptureStepsStore
    let eventSteps: CaptureStepsStore

    @State private var editorTarget: EditorTarget?
    @State private var pendingEditorTarget: EditorTarget?
    @State private var guestDestination: GuestDestination?

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

    /// A fallback guest pushes its existing home page from this page's navigation
    /// context. Custom Actions remain sheets because their live-mirroring editor is
    /// already a sheet everywhere else; the other providers retain their normal
    /// pushed management pages (ADR 0045).
    private enum GuestDestination: Hashable {
        case shortcut(String)
        case provider(ProviderID)
    }

    /// A fallback-eligible Custom Action belongs to its resolved ladder section, not
    /// a duplicate authoring row. This leaves only static links and non-text-first
    /// templates in Other actions (ADR 0045).
    private var otherActions: [(stored: StoredCustomAction, action: Action)] {
        customActions
            .compactMap { stored in
                guard let action = stored.definition.makeAction(id: stored.id), !action.isFallbackEligible else {
                    return nil
                }
                return (stored, action)
            }
            .sorted {
                let order = $0.stored.title.localizedCaseInsensitiveCompare($1.stored.title)
                return order == .orderedSame ? $0.stored.id < $1.stored.id : order == .orderedAscending
            }
    }

    // Pushed onto the launcher's navigation stack — the back chevron and edge-swipe
    // handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019): the Custom Actions schema's two
            // settings and Catalog's sole entry point form one Options section. Keep
            // the settings rendered through OptionRow: Core still declares their
            // structure, while this page supplies the closely-related destination.
            Section {
                ForEach(ProviderID.customActions.settingsSchema) { option in
                    OptionRow(provider: .customActions, option: option)
                }
                // The Catalog's single entry point (CONTEXT.md → Catalog; ADR 0028;
                // issue #143) follows Enabled and Fallbacks in the same section.
                NavigationLink { CatalogView() } label: {
                    Label("Browse catalog", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("browse-catalog")
            } header: {
                Text("Options")
            }

            // The Custom Actions page owns this cross-provider ordering surface. Its
            // guests (Shortcuts and built-in captures) live only in this ladder.
            FallbackListSections(
                store: store,
                enablement: enablement,
                eligible: eligible,
                caption: caption,
                onSelect: select
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
                ForEach(otherActions, id: \.stored.id) { entry in
                    CustomActionsListRow(
                        action: entry.action,
                        style: .other(
                            isDisabled: enablement.isDisabled(entry.stored.id),
                            onToggleDisabled: { enablement.toggleDisabled(entry.stored.id) }
                        ),
                        caption: entry.stored.urlString,
                        onPrimary: {},
                        onShelve: nil,
                        onSelect: { editorTarget = .edit(entry.stored) }
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
        .navigationDestination(item: $guestDestination) { destination in
            switch destination {
            case .shortcut(let name):
                ShortcutDetailView(name: name, store: shortcuts, enablement: enablement)
            case .provider(.reminders):
                CaptureStepsPage<ReminderStep>(provider: .reminders, store: reminderSteps)
            case .provider(.events):
                CaptureStepsPage<EventStep>(provider: .events, store: eventSteps)
            case .provider(.pile):
                ProviderOptionsPage(provider: .pile)
            case .provider(.snippets):
                SnippetManagerView(enablement: enablement)
            case .provider:
                EmptyView()
            }
        }
    }

    /// All fallback rows use one presentation contract. A Custom Action's caption is
    /// its actual URL template; guests say what they are, rather than pretending to
    /// own a URL. The action id is the stable bridge from the Core index to SwiftData.
    private func caption(for action: Action) -> String {
        if action.kind == .customAction,
           let stored = customActions.first(where: { $0.id == action.id }) {
            return stored.urlString
        }

        switch action.kind {
        case .shortcut:
            return "Shortcut"
        case .saveForLater, .newSnippet, .reminder, .event:
            return "Built-in capture"
        default:
            return action.kind.rawValue
        }
    }

    /// Custom Actions edit in their live-mirroring sheet; guest rows push the home
    /// page that owns their settings. The fallback list stays a pure projection of
    /// Core's tiers, with navigation kept at this UI edge.
    private func select(_ action: Action) {
        if action.kind == .customAction,
           let stored = customActions.first(where: { $0.id == action.id }) {
            editorTarget = .edit(stored)
            return
        }

        switch action.kind {
        case .shortcut:
            guestDestination = .shortcut(action.title)
        case .reminder:
            guestDestination = .provider(.reminders)
        case .event:
            guestDestination = .provider(.events)
        case .saveForLater:
            guestDestination = .provider(.pile)
        case .newSnippet:
            guestDestination = .provider(.snippets)
        default:
            break
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
