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
            // Dragging the form dismisses the keyboard, so the lower sections (the
            // fallback toggle, the alias field) are reachable after typing the URL
            // rather than staying pinned under the keyboard.
            .scrollDismissesKeyboard(.immediately)
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
                ArgumentRowEditor(def: $def, index: item.offset, row: item.element)
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

/// One live-mirrored argument row (CONTEXT.md → Argument; ADR 0021, issue #96): a
/// `{token}` name field, a **type picker** (text / number / date / choice), and the
/// per-type config it reveals — a choice's inline options, or a date's optional
/// output-format overrides. Every control binds to the `CustomActionDefinition` by
/// fill-order **position**, so a rename rewrites the URL token live (the row keeps
/// its identity and focus) and the type config tracks the slot.
private struct ArgumentRowEditor: View {
    @Binding var def: CustomActionDefinition
    let index: Int
    let row: ArgumentRow

    /// The slot's current spec — its type and per-type config.
    private var spec: ArgumentSpec { def.spec(at: index) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameAndTypeRow
            switch spec.type {
            case .choice: choiceOptionsEditor
            case .date: dateFormatField
            case .text, .number: EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    /// The `{token}` glyph, the name field (bound by position so typing rewrites the
    /// URL token live while the cursor stays put), and a compact **type menu** on the
    /// trailing edge — the same menu-style `Picker` the Appearance setting uses, which
    /// fits the row where the four-segment control was cramped.
    private var nameAndTypeRow: some View {
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
            Spacer(minLength: 8)
            typeMenu
        }
    }

    /// The type menu. Setting a slot to **choice** seeds one empty option so there
    /// is a field to type into; the other config is left intact across type changes.
    private var typeMenu: some View {
        Picker("Type", selection: Binding(
            get: { spec.type },
            set: { newType in
                var updated = spec
                updated.type = newType
                if newType == .choice && updated.options.isEmpty { updated.options = [""] }
                def.setSpec(at: index, to: updated)
            }
        )) {
            Text("Text").tag(ArgumentType.text)
            Text("Number").tag(ArgumentType.number)
            Text("Date").tag(ArgumentType.date)
            Text("Choice").tag(ArgumentType.choice)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("custom-action-type.\(row.name)")
    }

    /// The inline **choice options** editor: one text field per user-entered option
    /// (id = label; the chosen label fills the slot), each removable, plus an add
    /// button. Rows are spaced so the fields don't read as cramped. Save is gated on
    /// at least one non-blank option.
    private var choiceOptionsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(spec.options.enumerated()), id: \.offset) { item in
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Option", text: Binding(
                        get: { optionAt(item.offset) },
                        set: { setOption(item.offset, to: $0) }
                    ))
                    .accessibilityIdentifier("custom-action-choice-option.\(row.name).\(item.offset)")
                    Button {
                        removeOption(item.offset)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("custom-action-remove-option.\(row.name).\(item.offset)")
                }
            }
            Button {
                var updated = spec
                updated.options.append("")
                def.setSpec(at: index, to: updated)
            } label: {
                Label("Add option", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("custom-action-add-option.\(row.name)")
        }
        .padding(.leading, 20)
        .padding(.top, 2)
    }

    /// The single optional **date output-format** field (issue #96): its meaning
    /// decides whether the slot collects a date or a date-and-time — a format with a
    /// time raises a date+time picker, one without keeps it date-only — so there is no
    /// separate toggle. Blank uses the ISO `yyyy-MM-dd` default.
    private var dateFormatField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(ArgumentSpec.defaultDateOnlyFormat, text: formatBinding(\.dateFormat))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("custom-action-date-format.\(row.name)")
            Text("Blank uses \(ArgumentSpec.defaultDateOnlyFormat) (date only). Add a time — e.g. \(ArgumentSpec.defaultTimedFormat) — to pick a date and time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
    }

    // MARK: - Option + format bindings (by position, through the definition)

    private func optionAt(_ i: Int) -> String {
        let options = spec.options
        return options.indices.contains(i) ? options[i] : ""
    }

    private func setOption(_ i: Int, to value: String) {
        var updated = spec
        guard updated.options.indices.contains(i) else { return }
        updated.options[i] = value
        def.setSpec(at: index, to: updated)
    }

    private func removeOption(_ i: Int) {
        var updated = spec
        guard updated.options.indices.contains(i) else { return }
        updated.options.remove(at: i)
        def.setSpec(at: index, to: updated)
    }

    /// A `String` binding over one optional format field, mapping blank ↔ `nil` so an
    /// empty field falls back to the ISO default.
    private func formatBinding(_ keyPath: WritableKeyPath<ArgumentSpec, String?>) -> Binding<String> {
        Binding(
            get: { spec[keyPath: keyPath] ?? "" },
            set: { newValue in
                var updated = spec
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                updated[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
                def.setSpec(at: index, to: updated)
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
            fillOrder: orderedTokenNames,
            // Prune config for any token the template dropped (hard mirror) before it
            // is persisted, so a deleted slot leaves nothing behind.
            argumentSpecs: reconciledSpecs
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
            fillOrder: fillOrder,
            argumentSpecs: argumentSpecs
        )
    }

    /// Applies an edited definition back onto this row.
    func apply(_ def: CustomActionDefinition) {
        title = def.name
        urlString = def.template
        alias = def.aliases.first
        isFallback = def.isFallback
        fillOrder = def.orderedTokenNames
        argumentSpecs = def.reconciledSpecs
    }

    /// A fresh stored row from a saved definition — the create path's insert.
    static func make(from def: CustomActionDefinition) -> StoredCustomAction {
        StoredCustomAction(
            title: def.name,
            urlString: def.template,
            alias: def.aliases.first,
            isFallback: def.isFallback,
            fillOrder: def.orderedTokenNames,
            argumentSpecs: def.reconciledSpecs
        )
    }
}
