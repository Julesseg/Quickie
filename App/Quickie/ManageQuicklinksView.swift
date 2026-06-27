import SwiftUI
import SwiftData
import QuickieCore

/// The minimal manage surface for issue #5: create / edit / delete user
/// Quicklinks (name, URL template, optional alias, Fallback flag) and edit the
/// default search engine template. Deliberately plain — the polished settings
/// UX lands in a later slice; this exists so the M1 acceptance criteria are
/// reachable from the running app. The loop's logic is tested in QuickieCore;
/// this view is thin plumbing over the SwiftData store (ADR 0006).
struct ManageQuicklinksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredQuicklink.createdAt) private var quicklinks: [StoredQuicklink]

    /// The editable default search engine (issue #5 AC #6) — owned by RootView's
    /// app storage, edited here.
    @Binding var engineTemplate: String

    @State private var editing: StoredQuicklink?
    @State private var creatingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("https://…/search?q={query}", text: $engineTemplate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("engine-template-field")
                } header: {
                    Text("Default search engine")
                } footer: {
                    Text("The web-search Fallback uses this template. {query} is replaced by what you type.")
                }

                Section("Quicklinks") {
                    if quicklinks.isEmpty {
                        Text("No Quicklinks yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(quicklinks) { link in
                        Button {
                            editing = link
                        } label: {
                            QuicklinkRow(link: link)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Quicklinks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
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
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(quicklinks[index])
        }
    }
}

/// One row in the manage list: name, the template, and badges for alias /
/// Fallback so the user can tell at a glance how the Quicklink behaves.
private struct QuicklinkRow: View {
    let link: StoredQuicklink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(link.title)
                    .font(.body)
                if link.isFallback {
                    Text("Fallback")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
            }
            Text(link.urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// A plain value carrying the fields the editor collects, kept separate from the
/// `@Model` so creating and editing share one form without binding the form
/// straight to a managed object mid-edit.
struct QuicklinkDraft {
    var title: String = ""
    var urlString: String = ""
    var alias: String = ""
    var isFallback: Bool = false

    func makeModel() -> StoredQuicklink {
        StoredQuicklink(
            title: trimmedTitle,
            urlString: trimmedURL,
            alias: normalizedAlias,
            isFallback: effectiveFallback
        )
    }

    func apply(to model: StoredQuicklink) {
        model.title = trimmedTitle
        model.urlString = trimmedURL
        model.alias = normalizedAlias
        model.isFallback = effectiveFallback
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var normalizedAlias: String? {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Only a *placeholder*-Quicklink can be a Fallback (CONTEXT.md): a static
    /// link flagged as one would pin a row that ignores the typed text, so the
    /// flag is dropped when the template has no placeholder.
    private var effectiveFallback: Bool {
        isFallback && Action.templateHasPlaceholder(trimmedURL)
    }
}

/// The create/edit form. One screen for both: `link == nil` creates, otherwise
/// it pre-fills from the existing Quicklink. Saving hands a `QuicklinkDraft`
/// back to the caller, which decides whether to insert or mutate.
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
                alias: link.alias ?? "",
                isFallback: link.isFallback
            ))
        } else {
            _draft = State(initialValue: QuicklinkDraft())
        }
    }

    private var hasPlaceholder: Bool {
        Action.templateHasPlaceholder(draft.urlString)
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Open GitHub", text: $draft.title)
                        .accessibilityIdentifier("quicklink-title-field")
                }
                Section {
                    TextField("https://github.com/search?q={query}", text: $draft.urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quicklink-url-field")
                } header: {
                    Text("URL template")
                } footer: {
                    Text(hasPlaceholder
                         ? "Takes your typed text as its Argument (replaces {…})."
                         : "Opens directly — no placeholder, so it ignores typed text.")
                }
                Section("Alias (optional)") {
                    TextField("git", text: $draft.alias)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quicklink-alias-field")
                }
                if hasPlaceholder {
                    Section {
                        Toggle("Pin as Fallback", isOn: $draft.isFallback)
                            .accessibilityIdentifier("quicklink-fallback-toggle")
                    } footer: {
                        Text("A Fallback always appears in the bottom region, consuming whatever you type.")
                    }
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
