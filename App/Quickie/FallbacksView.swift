import SwiftUI
import SwiftData
import QuickieCore

/// The unified **Fallbacks** page (CONTEXT.md → Fallback list; ADR 0021): one
/// user-ordered list of every Fallback Action — fallback-flagged Custom Actions
/// plus the two permanent built-ins, Save for later and New Snippet. It reads
/// most-important-first (top = nearest the input/thumb in results). Rows can be
/// reordered, each can be **disabled** (kept in the list, hidden from results),
/// and only Custom Actions can be deleted — Save for later and New Snippet are
/// permanent (disable-only). Reached as the typed "Fallbacks" command row and
/// presented full-screen. This is the interim ordering/disable *and* authoring
/// surface; the dedicated Custom Actions editor + Management page are the next slice.
struct FallbacksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredCustomAction.createdAt) private var customActions: [StoredCustomAction]

    let store: FallbacksStore

    @State private var editing: StoredCustomAction?

    /// The display rows, in the user's reconciled order (most-important-first): each
    /// persisted id resolved to its fallback-flagged Custom Action or built-in. Only
    /// fallback-flagged Custom Actions belong on this ordering/disable surface
    /// (CONTEXT.md → Fallback list); a future non-fallback one (the next slice's
    /// Custom Actions page) is filtered out here.
    private var rows: [FallbackRow] {
        let fallbackCustomActions = customActions.filter(\.isFallback)
        let byID = Dictionary(uniqueKeysWithValues: fallbackCustomActions.map { ($0.id, $0) })
        return store.resolvedOrder(for: fallbackCustomActions.map(\.id)).compactMap { id in
            if let query = byID[id] { return .query(query) }
            switch id {
            case FallbacksStore.saveForLaterID: return .builtin(id: id, title: "Save for later")
            case FallbacksStore.newSnippetID: return .builtin(id: id, title: "New Snippet")
            default: return nil
            }
        }
    }

    // Pushed onto the launcher's navigation stack — no own stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019; issue #66): Options lead, the
            // user-ordered Fallback list follows.
            ProviderOptionsSection(provider: .fallbacks)

            Section {
                    ForEach(rows) { row in
                        FallbackRowView(
                            row: row,
                            isDisabled: store.isDisabled(row.id),
                            onToggleDisabled: { store.toggleDisabled(row.id) },
                            onEdit: { if case let .query(q) = row { editing = q } }
                        )
                        // Built-ins (Save for later / New Snippet) are permanent
                        // — only Custom Actions can be deleted.
                        .deleteDisabled(!row.isQuery)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } footer: {
                    Text("Top is most important — nearest the input in results. Disable to hide a fallback without removing it. Tap Edit to reorder. Save for later and New Snippet can't be deleted. Create a Custom Action on the Custom Actions page.")
                }
            }
            .navigationTitle("Fallbacks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            // A Custom Action row taps into the shared editor (ADR 0021; issue #94) —
            // the interim add/edit sheet is gone. Creating a new one lives on the
            // Custom Actions Management page; this page only orders and disables.
            .sheet(item: $editing) { action in
                CustomActionEditorView(definition: action.definition, isNew: false) { def in
                    action.apply(def)
                }
            }
    }

    /// Persists a reorder. We reconcile first so the saved order covers every
    /// live id, then apply the move and store it.
    private func move(from offsets: IndexSet, to destination: Int) {
        var ids = rows.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        store.setOrder(ids)
    }

    /// Deletes only Custom Actions — Save for later / New Snippet refuse
    /// deletion (CONTEXT.md → Fallback list). A swipe over a built-in row is a
    /// no-op.
    private func delete(_ offsets: IndexSet) {
        let current = rows
        for index in offsets {
            if case let .query(query) = current[index] {
                modelContext.delete(query)
            }
        }
    }
}

/// One entry in the Fallback list: a deletable fallback-flagged Custom Action, or a
/// permanent built-in (Save for later / New Snippet).
enum FallbackRow: Identifiable {
    case query(StoredCustomAction)
    case builtin(id: String, title: String)

    var id: String {
        switch self {
        case .query(let q): return q.id
        case .builtin(let id, _): return id
        }
    }

    var title: String {
        switch self {
        case .query(let q): return q.title
        case .builtin(_, let title): return title
        }
    }

    var subtitle: String? {
        switch self {
        case .query(let q): return q.urlString
        case .builtin: return nil
        }
    }

    var isQuery: Bool {
        if case .query = self { return true }
        return false
    }
}

/// A single Fallbacks-page row: title (+ template for a query), an enable/disable
/// toggle, and — for a Custom Action — a tap into its editor.
private struct FallbackRowView: View {
    let row: FallbackRow
    let isDisabled: Bool
    let onToggleDisabled: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // A per-row enable switch — disabling keeps the row in the list but
            // hides it from results.
            Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                .labelsHidden()
                .accessibilityIdentifier("fallback-enabled.\(row.id)")
        }
        .contentShape(Rectangle())
        .onTapGesture { if row.isQuery { onEdit() } }
    }
}

