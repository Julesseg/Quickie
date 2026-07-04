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
    /// renaming its URL token **per keystroke**. The rows are keyed by fill-order
    /// *position*, not by token name — a name-keyed row would change identity on
    /// every character and drop the field's focus — and each field binds straight to
    /// the model by position, so typing a name rewrites the `{token}` live while the
    /// cursor stays put. The footer states the order rule explicitly.
    private var argumentsSection: some View {
        Section {
            // Keyed by fill-order position (`\.offset`), not token name: a name-keyed
            // row changes identity on every keystroke and drops the field's focus.
            ForEach(Array(def.rows.enumerated()), id: \.offset) { item in
                argumentRow(index: item.offset, row: item.element)
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

    /// One argument row: a `{token}` glyph and a text field bound to the model by
    /// **position**, so typing rewrites the URL token live while the cursor stays put.
    private func argumentRow(index: Int, row: ArgumentRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(row.label, text: Binding(
                // A numeric auto-labeled token (`{1}`) shows blank under its
                // "Argument 1" placeholder — its name isn't a real label — while a
                // named token shows its name. Writing goes by position, so it needs no
                // stale captured name.
                get: { row.label == row.name ? row.name : "" },
                set: { def.setArgumentName(at: index, to: $0) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("custom-action-arg.\(row.name)")
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
