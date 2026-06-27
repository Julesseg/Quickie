import SwiftUI
import SwiftData

/// The Snippet library: create, list, edit, and delete the reusable copy-out
/// text that surfaces in the Result list (issue #6, acceptance criterion #1).
/// Deliberately a plain, conventional SwiftData list — the launcher's magic is
/// the input loop; managing snippets is ordinary CRUD that lives behind a sheet
/// so it never competes with the zero-wall launch (ADR 0012).
struct SnippetManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StoredSnippet.createdAt, order: .reverse) private var snippets: [StoredSnippet]

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

    var body: some View {
        NavigationStack {
            Group {
                if snippets.isEmpty {
                    ContentUnavailableView(
                        "No snippets yet",
                        systemImage: "doc.on.clipboard",
                        description: Text("Save reusable text — an address, a canned reply — and copy it from the result list.")
                    )
                } else {
                    List {
                        ForEach(snippets) { snippet in
                            Button {
                                editorTarget = .edit(snippet)
                            } label: {
                                SnippetRow(snippet: snippet)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("snippet-row-\(snippet.title)")
                        }
                        .onDelete(perform: delete)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
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
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(snippets[index])
        }
    }
}

/// One library row: the title with a one-line preview of the body so snippets
/// are distinguishable at a glance.
private struct SnippetRow: View {
    let snippet: StoredSnippet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.title)
                .font(.body)
                .foregroundStyle(.primary)
            Text(snippet.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
