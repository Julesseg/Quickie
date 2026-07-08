import SwiftUI
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The Quicklinks management page (CONTEXT.md → Quicklink, Management page; ADR
/// 0013): create / edit / delete user **static** Quicklinks (name, URL, optional
/// alias). A Quicklink opens directly — it carries no `{placeholder}` and
/// consumes no typed text, so the editor *rejects* a templated URL (that is a
/// Fallback query, managed on the Fallbacks page). Reached as the typed "Quicklinks"
/// command row and presented full-screen. Quickie ships no default Quicklinks.
struct QuicklinksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredQuicklink.createdAt) private var quicklinks: [StoredQuicklink]

    /// The instance-level Disabled state (issue #68): each row's toggle
    /// reversibly hides that one Quicklink from results/Recents/Favorites.
    let enablement: EnablementStore

    @State private var editing: StoredQuicklink?
    @State private var creatingNew = false

    // Pushed onto the launcher's navigation stack — the system back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019; issue #66): Options lead, the
            // provider's actions — the stored links — follow.
            ProviderOptionsSection(provider: .quicklinks)

            Section {
                if quicklinks.isEmpty {
                    Text("No Quicklinks yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(quicklinks) { link in
                    QuicklinkRow(
                        link: link,
                        isDisabled: enablement.isDisabled(link.actionID),
                        onToggleDisabled: { enablement.toggleDisabled(link.actionID) },
                        onEdit: { editing = link }
                    )
                }
                .onDelete(perform: delete)
            } header: {
                Text("Quicklinks")
            } footer: {
                Text("A Quicklink opens a fixed URL. For a search that consumes what you type, add a Fallback query on the Fallbacks page. Disable one to hide it from results without removing it.")
            }
        }
        .navigationTitle("Quicklinks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("add-quicklink")
                .accessibilityLabel("Add Quicklink")
            }
        }
        .sheet(isPresented: $creatingNew) {
            QuicklinkEditorView(link: nil) { draft in
                modelContext.insert(draft.makeModel())
            }
        }
        .sheet(item: $editing) { link in
            QuicklinkEditorView(link: link) { draft in
                draft.apply(to: link)
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(quicklinks[index])
        }
    }
}

/// One row in the Quicklinks list: name, its static URL, an enable/disable
/// toggle (the instance-level Disabled switch, issue #68), and a tap into the
/// editor — the same row shape as the Fallbacks page.
private struct QuicklinkRow: View {
    let link: StoredQuicklink
    let isDisabled: Bool
    let onToggleDisabled: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                Text(link.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Disabling keeps the row here but hides the Quicklink from every
            // launcher surface — reversible, unlike swipe-to-delete.
            Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                .labelsHidden()
                .accessibilityIdentifier("quicklink-enabled.\(link.id)")
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}

/// A plain value carrying the fields the editor collects, kept separate from the
/// `@Model` so creating and editing share one form without binding the form
/// straight to a managed object mid-edit.
struct QuicklinkDraft {
    var title: String = ""
    var urlString: String = ""
    var alias: String = ""

    func makeModel() -> StoredQuicklink {
        StoredQuicklink(title: trimmedTitle, urlString: trimmedURL, alias: normalizedAlias)
    }

    func apply(to model: StoredQuicklink) {
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

/// The create/edit form for a static Quicklink. One screen for both: `link == nil`
/// creates, otherwise it pre-fills from the existing Quicklink. A templated URL
/// (one with a `{placeholder}`) is rejected — that belongs on the Fallbacks page.
struct QuicklinkEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let link: StoredQuicklink?
    let onSave: (QuicklinkDraft) -> Void

    @State private var draft: QuicklinkDraft

    init(link: StoredQuicklink?, onSave: @escaping (QuicklinkDraft) -> Void) {
        self.link = link
        self.onSave = onSave
        if let link {
            _draft = State(initialValue: QuicklinkDraft(
                title: link.title,
                urlString: link.urlString,
                alias: link.alias ?? ""
            ))
        } else {
            _draft = State(initialValue: QuicklinkDraft())
        }
    }

    private var hasPlaceholder: Bool {
        Action.templateContainsPlaceholder(draft.urlString)
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasPlaceholder
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Open GitHub", text: $draft.title)
                        .accessibilityIdentifier("quicklink-title-field")
                }
                Section {
                    TextField("https://github.com", text: $draft.urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quicklink-url-field")
                } header: {
                    Text("URL")
                } footer: {
                    Text(hasPlaceholder
                         ? "A Quicklink can't contain a {placeholder}. Add it as a Fallback query instead."
                         : "Opens directly. Static link only — no typed text.")
                    .foregroundStyle(hasPlaceholder ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Section("Alias (optional)") {
                    TextField("git", text: $draft.alias)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quicklink-alias-field")
                }
            }
            .navigationTitle(link == nil ? "New Quicklink" : "Edit Quicklink")
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
                    .accessibilityIdentifier("save-quicklink")
                }
            }
        }
    }
}
