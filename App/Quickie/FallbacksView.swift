import SwiftUI
import SwiftData
import QuickieCore

/// The unified **Fallbacks** page (CONTEXT.md → Fallback list; ADR 0013): one
/// user-ordered list of every Fallback Action — Fallback queries plus the two
/// permanent built-ins, New Note and New Snippet. It reads most-important-first
/// (top = nearest the input/thumb in results). Rows can be reordered, each can be
/// **disabled** (kept in the list, hidden from results), and only Fallback queries
/// can be deleted — New Note and New Snippet are permanent (disable-only). Reached
/// as the typed "Fallbacks" command row and presented full-screen.
struct FallbacksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredFallbackQuery.createdAt) private var queries: [StoredFallbackQuery]

    let store: FallbacksStore

    @State private var editing: StoredFallbackQuery?
    @State private var creatingNew = false

    /// The display rows, in the user's reconciled order (most-important-first):
    /// each persisted id resolved to its Fallback query or built-in.
    private var rows: [FallbackRow] {
        let byID = Dictionary(uniqueKeysWithValues: queries.map { ($0.id, $0) })
        return store.resolvedOrder(for: queries.map(\.id)).compactMap { id in
            if let query = byID[id] { return .query(query) }
            switch id {
            case FallbacksStore.newNoteID: return .builtin(id: id, title: "New Note")
            case FallbacksStore.newSnippetID: return .builtin(id: id, title: "New Snippet")
            default: return nil
            }
        }
    }

    // Pushed onto the launcher's navigation stack — no own stack or Done button.
    var body: some View {
        List {
            Section {
                    ForEach(rows) { row in
                        FallbackRowView(
                            row: row,
                            isDisabled: store.isDisabled(row.id),
                            onToggleDisabled: { store.toggleDisabled(row.id) },
                            onEdit: { if case let .query(q) = row { editing = q } }
                        )
                        // Built-ins (New Note / New Snippet) are permanent —
                        // only Fallback queries can be deleted.
                        .deleteDisabled(!row.isQuery)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } footer: {
                    Text("Top is most important — nearest the input in results. Disable to hide a fallback without removing it. Tap Edit to reorder. New Note and New Snippet can't be deleted.")
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

    /// Deletes only Fallback queries — New Note / New Snippet refuse deletion
    /// (CONTEXT.md → Fallback list). A swipe over a built-in row is a no-op.
    private func delete(_ offsets: IndexSet) {
        let current = rows
        for index in offsets {
            if case let .query(query) = current[index] {
                modelContext.delete(query)
            }
        }
    }
}

/// One entry in the Fallback list: a deletable Fallback query, or a permanent
/// built-in (New Note / New Snippet).
enum FallbackRow: Identifiable {
    case query(StoredFallbackQuery)
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

/// A plain value carrying the fields the Fallback query editor collects.
struct FallbackQueryDraft {
    var title: String = ""
    var urlString: String = ""
    var alias: String = ""

    func makeModel() -> StoredFallbackQuery {
        StoredFallbackQuery(title: trimmedTitle, urlString: trimmedURL, alias: normalizedAlias)
    }

    func apply(to model: StoredFallbackQuery) {
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

/// The create/edit form for a Fallback query. A templated URL is **required** —
/// it must contain a `{placeholder}` the typed text fills (mirroring
/// `Action.fallbackQuery`), the inverse of the Quicklinks editor's rule.
struct FallbackQueryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let query: StoredFallbackQuery?
    let onSave: (FallbackQueryDraft) -> Void

    @State private var draft: FallbackQueryDraft

    init(query: StoredFallbackQuery?, onSave: @escaping (FallbackQueryDraft) -> Void) {
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
