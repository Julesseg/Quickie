import SwiftUI
import SwiftData
import QuickieCore
import QuickieStoreKit

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

    /// Whether this is a fresh action (drives the navigation title).
    let isNew: Bool
    let onSave: (CustomActionDefinition) -> Void

    /// The live view-model: a `CustomActionDefinition` whose `var` fields bind
    /// straight to the form, so `rows`/`arguments`/validation recompute per keystroke.
    @State private var def: CustomActionDefinition

    /// The URL field's caret, bound so the brace auto-close can place it
    /// **explicitly**: replacing a field's text programmatically resets the
    /// caret to the end, so after a rewrite the caret is re-placed from the
    /// rule's returned offset (between the pair after an auto-close, just past
    /// the close after a skip-over).
    @State private var templateSelection: TextSelection?

    /// View-side identity for each argument row, parallel to fill order. A row
    /// can't key by its token name (a rename changes it per keystroke, and the
    /// identity change would drop the field's focus) — but keying by *position*
    /// broke drag-to-reorder: after `onMove` the offsets 0…n-1 were still in
    /// ascending order, so SwiftUI saw an unchanged identity order and snapped the
    /// dragged row back. These UUIDs give each row an identity that survives a
    /// rename *and* is permuted alongside the model on a drag, so the move
    /// commits. Grown/truncated in step with the rows as the template gains and
    /// loses tokens (new tokens append to fill order, so appending fresh ids
    /// keeps existing rows' identities — and focus — stable).
    @State private var rowIDs: [UUID]

    init(
        definition: CustomActionDefinition,
        isNew: Bool,
        onSave: @escaping (CustomActionDefinition) -> Void
    ) {
        self.isNew = isNew
        self.onSave = onSave
        _def = State(initialValue: definition)
        _rowIDs = State(initialValue: definition.rows.map { _ in UUID() })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Add to Things", text: $def.name)
                        .accessibilityIdentifier("custom-action-name-field")
                }

                Section {
                    TextField(
                        "things:///add?title={title}&notes={notes}",
                        text: $def.template,
                        selection: $templateSelection,
                        axis: .vertical
                    )
                        .lineLimit(1...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("custom-action-url-field")
                        // Typing `{` auto-closes to `{}` with the caret between the
                        // pair; typing `}` against the auto-inserted close skips
                        // over it instead of doubling. The text and caret rules are
                        // pure and unit-tested in Core (`BraceAutoClose`); this
                        // replays them onto the binding, placing the caret
                        // explicitly because a programmatic text replacement would
                        // otherwise reset it to the end of the field.
                        //
                        // The rewrite is applied on the *next* main-loop tick, not
                        // inside this update: the field is still flushing the
                        // keystroke that triggered the change, and a rewrite issued
                        // mid-flush is overwritten by the field's own text sync
                        // (under fast/synthesized typing the auto-close never
                        // landed). The staleness guard drops the deferred rewrite
                        // if another edit arrived first, so it can never clobber
                        // newer input.
                        .onChange(of: def.template) { oldValue, newValue in
                            guard let adjustment = BraceAutoClose.adjusted(replacing: oldValue, with: newValue)
                            else { return }
                            Task { @MainActor in
                                guard def.template == newValue else { return }
                                def.template = adjustment.text
                                let caret = adjustment.text.index(
                                    adjustment.text.startIndex, offsetBy: adjustment.caretOffset
                                )
                                templateSelection = TextSelection(insertionPoint: caret)
                            }
                        }
                } header: {
                    Text("URL template")
                } footer: {
                    urlFooter
                }

                if def.hasSlot {
                    argumentsSection
                }

                symbolSection

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
            // Attached to the Form, not the arguments section — the section isn't
            // in the tree while the template has no slot, and the ids must track
            // the very edit that brings the first row in.
            .onChange(of: def.rows.count) { _, count in
                syncRowIDs(to: count)
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

    /// The URL field's footer: a scheme warning when the URL won't parse, and the
    /// **static link** note when it carries no `{name}` slot — a slot-less URL is a
    /// valid static Custom Action that opens directly (ADR 0030), not an error. A
    /// slotted URL needs no line: the Arguments section below lists what it found.
    @ViewBuilder
    private var urlFooter: some View {
        if !def.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !def.urlIsSchemedAfterProbe {
            Text("Add a scheme (like https:// or things://) so the URL can open.")
                .foregroundStyle(.red)
        } else if !def.hasSlot {
            Text("This link has no {slot}, so it opens directly — a static link.")
                .accessibilityIdentifier("custom-action-static-link-note")
        }
    }

    /// The live-mirrored argument rows in **fill order**, drag-to-reorder, each
    /// renaming its URL token **per keystroke**. The rows are keyed by the stable
    /// `rowIDs`, not by token name — a name-keyed row would change identity on
    /// every character and drop the field's focus — and each field binds straight to
    /// the model by position, so typing a name rewrites the `{token}` live while the
    /// cursor stays put. The footer states only the one rule the rows can't show:
    /// fill order is independent of where the slots sit in the URL.
    private var argumentsSection: some View {
        Section {
            ForEach(identifiedRows) { item in
                ArgumentRowEditor(def: $def, index: item.index, row: item.row)
            }
            .onMove { offsets, destination in
                // Permute the identities with the model, so the drag reads as a
                // real identity move and the drop commits.
                rowIDs.move(fromOffsets: offsets, toOffset: destination)
                def.moveArguments(fromOffsets: offsets, toOffset: destination)
            }
        } header: {
            HStack {
                // The accessibility value is the XCUITest-only order probe (see
                // `ReorderUITests` and the same probe on the Fallbacks page's
                // section headers): the fill order as stored, so a drag test can
                // tell a never-fired `onMove` from a committed-but-sprung-back row.
                Text("Arguments")
                    .accessibilityValue(
                        ProcessInfo.processInfo.arguments.contains("--uitesting")
                            ? def.rows.map(\.name).joined(separator: ",") : ""
                    )
                Spacer()
                EditButton()
                    .accessibilityIdentifier("custom-action-reorder")
            }
        } footer: {
            Text("Filled in this order, whatever order the slots appear in the URL.")
        }
    }

    /// One argument row paired with its stable view-side identity and its
    /// fill-order position (the position is what the row's bindings edit by).
    private struct IdentifiedArgumentRow: Identifiable {
        let id: UUID
        let index: Int
        let row: ArgumentRow
    }

    /// The rows zipped with `rowIDs`. `zip` truncates to the shorter side, so a
    /// frame where the template has changed but `syncRowIDs` hasn't run yet renders
    /// the paired prefix rather than crashing on a count mismatch.
    private var identifiedRows: [IdentifiedArgumentRow] {
        zip(rowIDs, def.rows.enumerated()).map { id, item in
            IdentifiedArgumentRow(id: id, index: item.offset, row: item.element)
        }
    }

    /// Keeps `rowIDs` the same length as the rows as the template gains and loses
    /// tokens. New tokens append to fill order, so appending fresh ids leaves every
    /// existing row's identity — and the focused field — untouched; on a loss the
    /// tail ids are dropped (identity for rows past a mid-list removal shifts, which
    /// is harmless: the edit that removed the token happened in the URL field, so no
    /// argument field held focus).
    private func syncRowIDs(to count: Int) {
        if rowIDs.count < count {
            rowIDs.append(contentsOf: (rowIDs.count..<count).map { _ in UUID() })
        } else if rowIDs.count > count {
            rowIDs.removeLast(rowIDs.count - count)
        }
    }

    /// The optional **appearance picker** (CONTEXT.md → Custom Action, Action color;
    /// issues #163, #243): one row previewing the composed badge that pushes the merged
    /// Symbol & Color page. Purely opt-in — leaving it at None/Default keeps the
    /// kind-derived badge on every surface, so an untouched action looks exactly as
    /// before.
    ///
    /// Symbol and colour share **one** row and one page rather than a row each. They are
    /// not two settings that happen to sit together: they compose into a single object —
    /// the badge — and the only question worth asking is "how does this action look?",
    /// which a preview of the composed result answers and two separate pickers cannot.
    private var symbolSection: some View {
        Section {
            NavigationLink {
                AppearancePickerView(glyph: $def.glyph, color: $def.color, kind: previewKind)
            } label: {
                HStack(spacing: 12) {
                    // Preview the leading badge exactly as a surface renders it: the
                    // chosen symbol over the chosen colour, or the derived glyph when
                    // None. Read through `normalizedGlyph` so a blank value previews the
                    // derived glyph rather than an empty badge.
                    ProviderBadge(kind: previewKind, symbol: def.normalizedGlyph, color: def.color)
                    Text("Symbol & Color")
                    Spacer(minLength: 8)
                    Text(appearanceValueLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("custom-action-appearance-row")
        }
    }

    /// The row's trailing summary: what the badge is currently made of. Both parts when
    /// both are set ("Mail · Teal"), the one that is set otherwise, and "Default" when
    /// neither is — so the row says what the page would show without opening it.
    private var appearanceValueLabel: String {
        switch (symbolValueLabel, def.color?.label) {
        case ("None", nil): return "Default"
        case ("None", let color?): return color
        case (let symbol, nil): return symbol
        case (let symbol, let color?): return "\(symbol) · \(color)"
        }
    }

    /// The kind the badge preview uses — the shared shape→kind rule (a slotted template
    /// is a Custom Action, a slot-less one a static link) so the preview tint matches
    /// what the action will actually wear.
    private var previewKind: ActionKind { def.derivedKind }

    /// The trailing value label on the symbol row: the chosen symbol's human name, or
    /// "None" when unset — read through the same normalization the surfaces use, so a
    /// blank glyph reads "None" here exactly as it renders the derived glyph elsewhere.
    private var symbolValueLabel: String {
        guard let glyph = def.normalizedGlyph else { return "None" }
        return CustomActionGlyphCatalog.all.first { $0.name == glyph }?.label ?? glyph
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
    /// separate toggle. Blank uses the ISO `yyyy-MM-dd` default. The two default
    /// formats sit beneath as one-tap fills: format strings are fiddly to type and
    /// the defaults cover almost every action, so each button stamps its string into
    /// the field — date-only, or the timed default whose time tokens flip the slot
    /// to a date-and-time picker.
    private var dateFormatField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(ArgumentSpec.defaultDateOnlyFormat, text: formatBinding(\.dateFormat))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("custom-action-date-format.\(row.name)")
            HStack(spacing: 8) {
                Button(ArgumentSpec.defaultDateOnlyFormat) {
                    setDateFormat(ArgumentSpec.defaultDateOnlyFormat)
                }
                .accessibilityIdentifier("custom-action-date-default.\(row.name)")
                Button(ArgumentSpec.defaultTimedFormat) {
                    setDateFormat(ArgumentSpec.defaultTimedFormat)
                }
                .accessibilityIdentifier("custom-action-datetime-default.\(row.name)")
            }
            // Bordered (not the Form default) so each button hit-tests on its own
            // frame rather than the whole row swallowing the tap.
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption.monospaced())
            Text("Blank uses \(ArgumentSpec.defaultDateOnlyFormat) (date only). Add a time — e.g. \(ArgumentSpec.defaultTimedFormat) — to pick a date and time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
    }

    /// Stamps a default format string into the date slot's config — the one-tap
    /// alternative to typing it (the field mirrors the value immediately).
    private func setDateFormat(_ format: String) {
        var updated = spec
        updated.dateFormat = format
        def.setSpec(at: index, to: updated)
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
            fillOrder: orderedTokenNames,
            // Prune config for any token the template dropped (hard mirror) before it
            // is persisted, so a deleted slot leaves nothing behind.
            argumentSpecs: reconciledSpecs,
            // The chosen glyph rides through untouched (issue #163) — a blank one was
            // already cleared to nil by the "No symbol" picker row.
            glyph: glyph,
            // The chosen colour likewise (issue #243): a typed palette token, so there
            // is nothing to normalize — "Default" is simply nil.
            color: color
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
            fillOrder: fillOrder,
            argumentSpecs: argumentSpecs,
            glyph: glyph,
            colorToken: colorToken
        )
    }

    /// Applies an edited definition back onto this row.
    func apply(_ def: CustomActionDefinition) {
        title = def.name
        urlString = def.template
        alias = def.aliases.first
        fillOrder = def.orderedTokenNames
        argumentSpecs = def.reconciledSpecs
        glyph = def.glyph
        colorToken = def.colorToken
    }

    /// A fresh stored row from a saved definition — the create path's insert. A
    /// Catalog install and the editor's Add both land here under a **fresh** UUID id
    /// (ADR 0028): installing mints a brand-new ordinary Custom Action every time.
    static func make(from def: CustomActionDefinition) -> StoredCustomAction {
        make(from: def, id: UUID().uuidString)
    }

    /// A stored row from a definition under an explicit id — the seed path's insert,
    /// which needs the fixed `seed.*` id (ADR 0023 dedup) rather than a fresh UUID.
    static func make(from def: CustomActionDefinition, id: String) -> StoredCustomAction {
        StoredCustomAction(
            id: id,
            title: def.name,
            urlString: def.template,
            alias: def.aliases.first,
            fillOrder: def.orderedTokenNames,
            argumentSpecs: def.reconciledSpecs,
            glyph: def.glyph,
            colorToken: def.colorToken
        )
    }
}
