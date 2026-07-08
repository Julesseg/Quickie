import SwiftUI
import QuickieCore

/// The small classification sheet the Share Extension presents (CONTEXT.md →
/// Share Extension): the URL branch is a Quicklink draft mirroring the in-app
/// Quicklink editor, and the text branch is a Snippet ⇄ Pile sheet — a Snippet
/// (default) with editable title and body, or a titleless Pile entry — each
/// mirroring its in-app editor's Save gate. The refusal states render here too:
/// unsupported payloads, and the App Group store being unavailable (ADR 0022 —
/// refuse honestly, never report a false save).
struct ShareSheetView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Save to Quickie")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { model.cancel() }
                    }
                    if isEditing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") { model.save() }
                                .disabled(!model.canSave)
                        }
                    }
                }
        }
    }

    private var isEditing: Bool {
        switch model.phase {
        case .editingQuicklink, .editingText: return true
        case .loading, .unsupported, .failed: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()

        case .editingQuicklink:
            quicklinkForm

        case .editingText:
            textForm

        case .unsupported(let message):
            refusal(message, systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")

        case .failed(let message):
            refusal(message, systemImage: "exclamationmark.triangle")
        }
    }

    private var quicklinkForm: some View {
        Form {
            Section("Name") {
                TextField("Open GitHub", text: $model.quicklinkDraft.title)
            }
            Section {
                TextField("https://github.com", text: $model.quicklinkDraft.urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("URL")
            } footer: {
                Text(hasPlaceholder
                     ? "A Quicklink can't contain a {placeholder}."
                     : "Saved as a Quicklink — opens directly from Quickie.")
                .foregroundStyle(hasPlaceholder ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            Section("Alias (optional)") {
                TextField("git", text: $model.quicklinkDraft.alias)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var hasPlaceholder: Bool {
        Action.templateContainsPlaceholder(model.quicklinkDraft.urlString)
    }

    /// The text branch: a Snippet ⇄ Pile switch at the top, then the fields for
    /// the chosen kind. Snippet is titled reusable copy-out text (editable title
    /// pre-filled from the first line, plus the editable body); a Pile entry is
    /// a single titleless block of deferred-query text.
    private var textForm: some View {
        Form {
            Section {
                Picker("Save as", selection: $model.textDraft.kind) {
                    Text("Snippet").tag(ShareModel.TextKind.snippet)
                    Text("Pile").tag(ShareModel.TextKind.pile)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("share-text-kind")
            }

            switch model.textDraft.kind {
            case .snippet:
                Section("Title") {
                    TextField("e.g. Home address", text: $model.textDraft.title)
                        .accessibilityIdentifier("share-snippet-title")
                }
                Section {
                    TextField("The text to copy", text: $model.textDraft.text, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("share-snippet-body")
                } header: {
                    Text("Body")
                } footer: {
                    Text("Saved as a Snippet — copies out from Quickie.")
                }
            case .pile:
                Section {
                    TextField("Text to save for later", text: $model.textDraft.text, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("share-pile-text")
                } footer: {
                    Text("Saved to the Pile — a query to deal with later.")
                }
            }
        }
    }

    /// An honest dead end: what happened, and the only exit is Cancel — the
    /// request is never completed as if something were saved.
    private func refusal(_ message: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label("Nothing saved", systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
