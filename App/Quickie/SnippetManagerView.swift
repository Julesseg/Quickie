import SwiftUI
import SwiftData

/// The Snippet library: create, list, edit, and delete the reusable copy-out
/// text that surfaces in the Result list (issue #6, acceptance criterion #1).
/// Deliberately a plain, conventional SwiftData list — the launcher's magic is
/// the input loop; managing snippets is ordinary CRUD on a pushed page
/// so it never competes with the zero-wall launch (ADR 0012).
struct SnippetManagerView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredSnippet.createdAt, order: .reverse) private var snippets: [StoredSnippet]

    /// The instance-level Disabled state (issue #68): each row's toggle
    /// reversibly hides that one Snippet from results/Recents/Favorites.
    let enablement: EnablementStore

    /// What the editor sheet is doing — composing a new snippet or editing an
    /// existing one. A single optional drives one sheet, sidestepping the
    /// SwiftUI multiple-`.sheet`-on-one-view gotcha and keeping add and edit on
    /// one path.
    @State private var editorTarget: EditorTarget?

    private enum EditorTarget: Identifiable {
        case new
        case edit(StoredSnippet)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let snippet): return "edit-\(snippet.persistentModelID.hashValue)"
            }
        }
    }

    // Pushed onto the launcher's navigation stack — the back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        // The unified page shape (ADR 0019; issue #66): Options lead, the
        // snippet library follows — so the empty state now sits inside the
        // list, beneath the always-present Options section.
        List {
            ProviderOptionsSection(provider: .snippets)

            if snippets.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No snippets yet",
                        systemImage: "doc.on.clipboard",
                        description: Text("Save reusable text — an address, a canned reply — and copy it from the result list.")
                    )
                }
            } else {
                Section {
                    ForEach(snippets) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            isDisabled: enablement.isDisabled(snippet.actionID),
                            onToggleDisabled: { enablement.toggleDisabled(snippet.actionID) },
                            onEdit: { editorTarget = .edit(snippet) }
                        )
                        .accessibilityIdentifier("snippet-row-\(snippet.title)")
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Disable a snippet to hide it from results without removing it.")
                }
            }
        }
        .navigationTitle("Snippets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("snippet-add")
            }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                SnippetEditorView(snippet: nil)
            case .edit(let snippet):
                SnippetEditorView(snippet: snippet)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(snippets[index])
        }
    }
}

/// One library row: the title with a one-line preview of the body so snippets
/// are distinguishable at a glance, plus an enable/disable toggle (the
/// instance-level Disabled switch, issue #68) and a tap into the editor.
private struct SnippetRow: View {
    let snippet: StoredSnippet
    let isDisabled: Bool
    let onToggleDisabled: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.title)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                Text(snippet.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Disabling keeps the row here but hides the Snippet from every
            // launcher surface — reversible, unlike swipe-to-delete.
            Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                .labelsHidden()
                .accessibilityIdentifier("snippet-enabled.\(snippet.id)")
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}
