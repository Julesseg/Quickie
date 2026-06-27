import SwiftUI
import SwiftData

/// Create or edit a single Snippet — a title and its copy-out body. A `nil`
/// snippet means "create"; an existing one means "edit", and the same form
/// serves both. Saving inserts or updates in SwiftData; the in-memory index is
/// rebuilt from the store on the next query (ADR 0006).
struct SnippetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The snippet under edit, or `nil` when composing a new one.
    let snippet: StoredSnippet?

    @State private var title: String
    @State private var bodyText: String

    init(snippet: StoredSnippet?) {
        self.snippet = snippet
        _title = State(initialValue: snippet?.title ?? "")
        _bodyText = State(initialValue: snippet?.body ?? "")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Home address", text: $title)
                        .accessibilityIdentifier("snippet-title-field")
                }
                Section("Body") {
                    TextField("The text to copy", text: $bodyText, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("snippet-body-field")
                }
            }
            .navigationTitle(snippet == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                        .accessibilityIdentifier("snippet-save")
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let snippet {
            snippet.title = trimmedTitle
            snippet.body = trimmedBody
        } else {
            context.insert(StoredSnippet(title: trimmedTitle, body: trimmedBody))
        }
        dismiss()
    }
}
