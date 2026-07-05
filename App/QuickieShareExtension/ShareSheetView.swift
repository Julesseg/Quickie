import SwiftUI
import QuickieCore

/// The small classification sheet the Share Extension presents (CONTEXT.md →
/// Share Extension): this slice carries the URL branch — a Quicklink draft
/// with quick edit, mirroring the in-app Quicklink editor's fields and its
/// Save gate. The refusal states render here too: unsupported payloads, and
/// the App Group store being unavailable (ADR 0022 — refuse honestly, never
/// report a false save).
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
                    if case .editing = model.phase {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") { model.save() }
                                .disabled(!model.canSave)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()

        case .editing:
            quicklinkForm

        case .unsupported(let message):
            refusal(message, systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")

        case .failed(let message):
            refusal(message, systemImage: "exclamationmark.triangle")
        }
    }

    private var quicklinkForm: some View {
        Form {
            Section("Name") {
                TextField("Open GitHub", text: $model.draft.title)
            }
            Section {
                TextField("https://github.com", text: $model.draft.urlString)
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
                TextField("git", text: $model.draft.alias)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var hasPlaceholder: Bool {
        Action.templateContainsPlaceholder(model.draft.urlString)
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
