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
    @State private var creatingNew = false

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
                        // — only Fallback queries can be deleted.
                        .deleteDisabled(!row.isQuery)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } footer: {
                    Text("Top is most important — nearest the input in results. Disable to hide a fallback without removing it. Tap Edit to reorder. Save for later and New Snippet can't be deleted.")
                }
            }
            .navigationTitle("Fallbacks")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button {
                        creatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("add-fallback-query")
                    .accessibilityLabel("Add Fallback query")
                }
            }
            .sheet(isPresented: $creatingNew) {
                FallbackQueryEditorView(query: nil) { draft in
                    modelContext.insert(draft.makeModel())
                }
            }
            .sheet(item: $editing) { query in
                FallbackQueryEditorView(query: query) { draft in
                    draft.apply(to: query)
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

    /// Deletes only Fallback queries — Save for later / New Snippet refuse
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
/// toggle, and — for a Fallback query — a tap into its editor.
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

/// A plain value carrying the fields the interim Custom Action editor collects
/// (name + URL template). All detected `{name}` slots are text Arguments; the real
/// per-argument editor is the next slice (ADR 0021).
struct FallbackQueryDraft {
    var title: String = ""
    var urlString: String = ""
    var alias: String = ""

    func makeModel() -> StoredCustomAction {
        // Authored on the Fallbacks page, so it is a fallback-flagged Custom Action
        // (CONTEXT.md → Fallback Action).
        StoredCustomAction(title: trimmedTitle, urlString: trimmedURL, alias: normalizedAlias, isFallback: true)
    }

    func apply(to model: StoredCustomAction) {
        model.title = trimmedTitle
        model.urlString = trimmedURL
        model.alias = normalizedAlias
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var normalizedAlias: String? {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The interim create/edit form for a Custom Action (ADR 0021). A templated URL is
/// **required** — it must contain at least one `{name}` slot the breadcrumb fills
/// (mirroring `CustomActionDefinition`), the inverse of the Quicklinks editor's rule.
struct FallbackQueryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let query: StoredCustomAction?
    let onSave: (FallbackQueryDraft) -> Void

    @State private var draft: FallbackQueryDraft

    init(query: StoredCustomAction?, onSave: @escaping (FallbackQueryDraft) -> Void) {
        self.query = query
        self.onSave = onSave
        if let query {
            _draft = State(initialValue: FallbackQueryDraft(
                title: query.title,
                urlString: query.urlString,
                alias: query.alias ?? ""
            ))
        } else {
            _draft = State(initialValue: FallbackQueryDraft())
        }
    }

    private var hasPlaceholder: Bool {
        Action.templateContainsPlaceholder(draft.urlString)
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasPlaceholder
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Search the web", text: $draft.title)
                        .accessibilityIdentifier("fallback-title-field")
                }
                Section {
                    TextField("https://duckduckgo.com/?q={query}", text: $draft.urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("fallback-url-field")
                } header: {
                    Text("URL template")
                } footer: {
                    Text(hasPlaceholder
                         ? "Replaces {…} with whatever you type."
                         : "Add a {placeholder} — a Fallback query must consume your typed text.")
                    .foregroundStyle(hasPlaceholder || draft.urlString.isEmpty
                                     ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                }
                Section("Alias (optional)") {
                    TextField("search", text: $draft.alias)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("fallback-alias-field")
                }
            }
            .navigationTitle(query == nil ? "New Fallback query" : "Edit Fallback query")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("save-fallback-query")
                }
            }
        }
    }
}
