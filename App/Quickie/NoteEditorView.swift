import SwiftUI
import SwiftData

/// Read, create, or edit a single Note — the brain-dump target whose main
/// action is **Open/read** (CONTEXT.md → Note). A `nil` note means "create"; an
/// existing one means "open/read", and the same form lets the user read the body
/// and edit it inline — appending is just typing at the end of the editable
/// body. Saving inserts or updates in SwiftData; the in-memory index is rebuilt
/// from the store on the next query (ADR 0006).
///
/// This is the single surface behind both the library (tap a row to open) and
/// the Result list (a note's main action opens it here) — read and edit share
/// one screen, since a Note is something you reopen and keep adding to.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The note under read/edit, or `nil` when composing a new one.
    let note: StoredNote?

    @State private var title: String
    @State private var bodyText: String

    init(note: StoredNote?) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _bodyText = State(initialValue: note?.body ?? "")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. App ideas", text: $title)
                        .accessibilityIdentifier("note-title-field")
                }
                Section("Note") {
                    TextField("Your thoughts…", text: $bodyText, axis: .vertical)
                        .lineLimit(5...20)
                        .accessibilityIdentifier("note-body-field")
                }
            }
            .navigationTitle(note == nil ? "New Note" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                        .accessibilityIdentifier("note-save")
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let note {
            note.title = trimmedTitle
            note.body = trimmedBody
            note.updatedAt = Date()
        } else {
            context.insert(StoredNote(title: trimmedTitle, body: trimmedBody))
        }
        dismiss()
    }
}
