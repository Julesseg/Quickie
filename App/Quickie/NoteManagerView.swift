import SwiftUI
import SwiftData

/// The Note library: create, list, open/read, edit, append, and delete the
/// captured free-text thoughts that surface in the Result list (issue #7). Like
/// the Snippet library it is a plain, conventional SwiftData list on a pushed
/// page — the launcher's magic is the input loop and the instant "New Note" capture;
/// managing notes afterwards is ordinary CRUD that never competes with the
/// zero-wall launch (ADR 0012). Notes are ordered most-recently-touched first so
/// the active brain-dump is always on top.
struct NoteManagerView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredNote.updatedAt, order: .reverse) private var notes: [StoredNote]

    /// What the editor sheet is doing — composing a new note or opening an
    /// existing one. A single optional drives one sheet, sidestepping the
    /// SwiftUI multiple-`.sheet`-on-one-view gotcha and keeping add and open on
    /// one path.
    @State private var editorTarget: EditorTarget?

    private enum EditorTarget: Identifiable {
        case new
        case open(StoredNote)

        var id: String {
            switch self {
            case .new: return "new"
            case .open(let note): return "open-\(note.persistentModelID.hashValue)"
            }
        }
    }

    // Pushed onto the launcher's navigation stack — the back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        // The unified page shape (ADR 0019; issue #66): Options lead, the note
        // library follows — so the empty state now sits inside the list,
        // beneath the always-present Options section.
        List {
            ProviderOptionsSection(provider: .notes)

            if notes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Capture a thought — type it and pick “New Note”, or add one here — then reopen it to read or add more.")
                    )
                }
            } else {
                Section {
                    ForEach(notes) { note in
                        Button {
                            editorTarget = .open(note)
                        } label: {
                            NoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("note-row-\(note.title)")
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("note-add")
            }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                NoteEditorView(note: nil)
            case .open(let note):
                NoteEditorView(note: note)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(notes[index])
        }
    }
}

/// One library row: the title with a one-line preview of the body so notes are
/// distinguishable at a glance.
private struct NoteRow: View {
    let note: StoredNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.body)
                .foregroundStyle(.primary)
            Text(note.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
