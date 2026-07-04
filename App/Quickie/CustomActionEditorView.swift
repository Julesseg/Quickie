import SwiftUI
import SwiftData
import QuickieCore

/// The **Custom Action editor** (CONTEXT.md → Custom Action; ADR 0021, issue #94):
/// a live-mirroring form whose argument rows *are* the URL template's `{name}`
/// slots. Typing the URL grows and shrinks the rows beneath it (hard mirror — a
/// deleted token drops its row immediately), renaming a row rewrites the URL token
/// in place, and dragging the rows sets the **fill order** the breadcrumb asks in
/// (independent of the URL's own order). The whole surface sits on one Core value,
/// `CustomActionDefinition`, whose pure reconciliation and validation this view only
/// renders — the editor is the validator (Save is gated on `isValidForSave`), so the
/// runtime keeps its silent no-op.
///
/// One screen for both create and edit: the parent hands an initial definition and
/// an `onSave`, and owns the SwiftData write (insert vs. apply). Reached from the
/// Custom Actions Management page (create + edit) and the Fallbacks page (edit).
struct CustomActionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// Whether this is a fresh action (drives the title and the fallback-default).
    let isNew: Bool
    let onSave: (CustomActionDefinition) -> Void

    /// The live view-model: a `CustomActionDefinition` whose `var` fields bind
    /// straight to the form, so `rows`/`arguments`/validation recompute per keystroke.
    @State private var def: CustomActionDefinition

    init(
        definition: CustomActionDefinition,
        isNew: Bool,
        onSave: @escaping (CustomActionDefinition) -> Void
    ) {
        self.isNew = isNew
        self.onSave = onSave
        _def = State(initialValue: definition)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Add to Things", text: $def.name)
                        .accessibilityIdentifier("custom-action-name-field")
                }

                Section {
                    TextField("things:///add?title={title}&notes={notes}", text: $def.template)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("custom-action-url-field")
                } header: {
                    Text("URL template")
                } footer: {
                    urlFooter
                }

                if def.hasSlot {
                    argumentsSection
                    fallbackSection
                }

                Section("Alias (optional)") {
                    TextField("things", text: aliasBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("custom-action-alias-field")
                }
            }
            .navigationTitle(isNew ? "New Custom Action" : "Edit Custom Action")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(def.saved())
                        dismiss()
                    }
                    .disabled(!def.isValidForSave)
                    .accessibilityIdentifier("save-custom-action")
                }
            }
        }
    }

    /// The URL field's footer: the slot-less **Quicklink redirect** when a URL
    /// carries no `{name}` (a static link isn't a Custom Action), a scheme warning
    /// once slots exist but the URL won't parse, and the plain hint otherwise.
    @ViewBuilder
    private var urlFooter: some View {
        if !def.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !def.hasSlot {
            Text("This link has no {slot}, so it opens nothing to fill. A static link is a Quicklink — add it on the Quicklinks page instead.")
                .foregroundStyle(.red)
                .accessibilityIdentifier("custom-action-quicklink-redirect")
        } else if def.hasSlot && !def.urlIsSchemedAfterProbe {
            Text("Add a scheme (like https:// or things://) so the filled URL can open.")
                .foregroundStyle(.red)
        } else {
            Text("Each {name} becomes an argument the breadcrumb fills, then opens the URL.")
        }
    }

    /// The live-mirrored argument rows in **fill order**, drag-to-reorder, each
    /// renaming its URL token. The footer states the order rule explicitly.
    private var argumentsSection: some View {
        Section {
            ForEach(def.rows) { row in
                ArgumentRowField(
                    row: row,
                    onRename: { newName in def.renameArgument(row.name, to: newName) }
                )
            }
            .onMove { offsets, destination in
                def.moveArguments(fromOffsets: offsets, toOffset: destination)
            }
        } header: {
            HStack {
                Text("Arguments")
                Spacer()
                EditButton()
                    .accessibilityIdentifier("custom-action-reorder")
            }
        } footer: {
            Text("The breadcrumb asks for these in this order — drag to reorder. This fill order is independent of where the slots sit in the URL. Rename a row to rewrite its {token}.")
        }
    }

    /// The **fallback flag**, gated on the first argument by fill order being free
    /// text (ADR 0021). This slice is text-only, so it is enabled whenever there is a
    /// first argument; the gate keys off fill order so it stays correct once types land.
    private var fallbackSection: some View {
        Section {
            Toggle("Show as a fallback", isOn: $def.isFallback)
                .disabled(!def.canBeFallback)
                .accessibilityIdentifier("custom-action-fallback-toggle")
        } footer: {
            Text(def.canBeFallback
                 ? "On always surfaces this in the fallback region, seeding your typed text as the first argument."
                 : "A fallback seeds your typed text into its first argument, so the first argument must be free text.")
        }
    }

    /// Bridges the model's single optional `alias` to the definition's `aliases`
    /// array — the editor collects at most one alias, matching the other editors.
    private var aliasBinding: Binding<String> {
        Binding(
            get: { def.aliases.first ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                def.aliases = trimmed.isEmpty ? [] : [trimmed]
            }
        )
    }
}

/// One argument row's rename field (ADR 0021, issue #94): edits the URL **token
/// name** in place. A numeric auto-labeled token (`{1}`) starts blank under its
/// "Argument 1" placeholder — its name isn't a real label — while a named token
/// shows its name. Committing a non-empty change rewrites the token. Local `@State`
/// holds the in-progress text so a per-keystroke token rewrite (which would change
/// the row's identity and end the edit) is avoided; the rename lands on submit or
/// when the field loses focus.
private struct ArgumentRowField: View {
    let row: ArgumentRow
    let onRename: (String) -> Void

    @State private var text: String

    init(row: ArgumentRow, onRename: @escaping (String) -> Void) {
        self.row = row
        self.onRename = onRename
        // A numeric auto-labeled row (label differs from the raw name) starts blank;
        // a named row seeds the field with its current name.
        _text = State(initialValue: row.label == row.name ? row.name : "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(row.label, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("custom-action-arg.\(row.name)")
                .onSubmit(commit)
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != row.name else { return }
        onRename(trimmed)
    }
}

extension CustomActionDefinition {
    /// A save-ready copy: name and template trimmed, and the resolved fill order
    /// baked into `fillOrder` so the persisted order survives even if the stored
    /// template's tokens are later reconciled. The parent persists this value.
    func saved() -> CustomActionDefinition {
        CustomActionDefinition(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: aliases,
            template: template.trimmingCharacters(in: .whitespacesAndNewlines),
            isFallback: isFallback,
            fillOrder: orderedTokenNames
        )
    }
}

extension StoredCustomAction {
    /// The Core definition this stored row drives — the editor's starting value.
    var definition: CustomActionDefinition {
        CustomActionDefinition(
            name: title,
            aliases: alias.map { [$0] } ?? [],
            template: urlString,
            isFallback: isFallback,
            fillOrder: fillOrder
        )
    }

    /// Applies an edited definition back onto this row.
    func apply(_ def: CustomActionDefinition) {
        title = def.name
        urlString = def.template
        alias = def.aliases.first
        isFallback = def.isFallback
        fillOrder = def.orderedTokenNames
    }

    /// A fresh stored row from a saved definition — the create path's insert.
    static func make(from def: CustomActionDefinition) -> StoredCustomAction {
        StoredCustomAction(
            title: def.name,
            urlString: def.template,
            alias: def.aliases.first,
            isFallback: def.isFallback,
            fillOrder: def.orderedTokenNames
        )
    }
}
