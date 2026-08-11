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
                    eligibilityNote
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
            // PROTOTYPE (throwaway): the floating variant pill — overlays the whole
            // stack so it stays visible on the pushed picker pages too.
            #if DEBUG
            .overlay(alignment: .bottom) {
                ColorPickerPrototypeSwitcher()
            }
            #endif
        }
    }

    /// The URL field's footer: a scheme warning when the URL won't parse, the plain
    /// slotted hint when the URL carries `{name}` slots, and the **static link** note
    /// when it has none — a slot-less URL is a valid static Custom Action that opens
    /// directly (ADR 0030), not an error.
    @ViewBuilder
    private var urlFooter: some View {
        if !def.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !def.urlIsSchemedAfterProbe {
            Text("Add a scheme (like https:// or things://) so the URL can open.")
                .foregroundStyle(.red)
        } else if def.hasSlot {
            Text("Each {name} becomes an argument the breadcrumb fills, then opens the URL.")
        } else {
            Text("This link has no {slot}, so it opens directly — a static link.")
                .accessibilityIdentifier("custom-action-static-link-note")
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

    /// The **fallback-eligibility note** (issue #114): there is no fallback control —
    /// eligibility is derived from shape, never declared. When the first fill-order
    /// argument is free text the action *can* be added to the Fallbacks page's pool;
    /// this line tells the user where activation lives (and, when the first argument
    /// isn't free text, why it isn't offered). Informational only, so a section footer.
    private var eligibilityNote: some View {
        Section {
            EmptyView()
        } footer: {
            Text(def.isFallbackEligible
                 ? "This action can be a fallback — add it on the Fallbacks page to have it consume your typed text as the first argument."
                 : "To use this as a fallback (consuming your typed text), make its first argument free text.")
                .accessibilityIdentifier("custom-action-eligibility-note")
        }
    }

    /// The optional **glyph picker** (CONTEXT.md → Custom Action; issue #163): a
    /// navigation row previewing the current symbol (or "None") that pushes the
    /// curated, fuzzy-searchable `GlyphPickerView`. Purely opt-in — leaving it "None"
    /// keeps the kind-derived leading glyph on every surface, so an untouched action
    /// looks exactly as before.
    /// The shipped Symbol row, unchanged — a navigation row previewing the current
    /// symbol (or "None") that pushes the curated, fuzzy-searchable `GlyphPickerView`.
    private var shippedSymbolRow: some View {
        NavigationLink {
            GlyphPickerView(selection: $def.glyph)
        } label: {
            HStack(spacing: 12) {
                // Preview the leading badge exactly as a surface renders it: the
                // chosen symbol over the chosen colour (or the kind's tint), or the
                // derived glyph when None. Read through `normalizedGlyph` so a blank
                // value previews the derived glyph rather than an empty badge.
                ProviderBadge(kind: previewKind, symbol: def.normalizedGlyph, color: def.color)
                Text("Symbol")
                Spacer(minLength: 8)
                Text(symbolValueLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("custom-action-symbol-row")
    }

    private var symbolSection: some View {
        Section {
            // PROTOTYPE (throwaway): variant D merges symbol + color into one page,
            // so the gate hides this shipped Symbol row while D is active.
            #if DEBUG
            PrototypeSymbolRowGate { shippedSymbolRow }
            #else
            shippedSymbolRow
            #endif

            // PROTOTYPE (throwaway): DEBUG builds swap the shipped Color row for the
            // variant under evaluation — see PrototypeColorPickerVariants.swift.
            #if DEBUG
            PrototypeColorRow(def: $def, previewKind: previewKind)
                .accessibilityIdentifier("custom-action-color-row")
            #else
            // The colour picker sits directly beside the glyph picker — the two are
            // siblings (CONTEXT.md → Action color; issue #243), one section, one preview
            // badge each, both purely opt-in.
            NavigationLink {
                ActionColorPickerView(selection: $def.color)
            } label: {
                HStack(spacing: 12) {
                    // A bare **swatch**, not a second copy of the badge above: the row
                    // beside it already previews the composed badge, and repeating it
                    // here would say nothing new (two identical badges stacked read as a
                    // rendering fault). This shows the one thing this row controls.
                    ActionColorSwatch(color: def.color)
                    Text("Color")
                    Spacer(minLength: 8)
                    Text(def.color?.label ?? "Default")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("custom-action-color-row")
            #endif
        } footer: {
            Text("Give this action its own symbol and color, shown everywhere it appears. Leave them as None and Default to use the ones its kind provides.")
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

/// The curated **glyph picker** (CONTEXT.md → Custom Action; issue #163): a
/// searchable gallery of SF Symbols the user can set as a Custom Action's leading
/// glyph, plus a "No symbol" row that clears back to the derived glyph. The search
/// reuses the same `Matcher` fuzzy-find furniture the choice input method uses
/// (`CustomActionGlyphCatalog.search`), so it ranks best-match-first exactly like a
/// breadcrumb choice step. Selecting a symbol writes the binding and pops back.
private struct GlyphPickerView: View {
    @Environment(\.dismiss) private var dismiss
    /// The definition's chosen glyph — written on selection, cleared by "No symbol".
    @Binding var selection: String?

    @State private var query = ""

    /// The curated options ranked by the shared fuzzy matcher — best first.
    private var results: [GlyphOption] {
        CustomActionGlyphCatalog.search(query)
    }

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                // The clear row leads so "back to the derived glyph" is always the
                // first, thumb-reachable choice — a curated set never buries the reset.
                GlyphClearCell(isSelected: selection == nil) {
                    selection = nil
                    dismiss()
                }
                ForEach(results) { option in
                    GlyphCell(option: option, isSelected: option.name == selection) {
                        selection = option.name
                        dismiss()
                    }
                }
            }
            .padding()
            if results.isEmpty {
                Text("No symbols match “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Symbol")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search symbols")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
}

/// One symbol cell in the picker: the glyph in a tinted badge over its label, with a
/// selection ring on the current choice.
private struct GlyphCell: View {
    let option: GlyphOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    Image(systemName: option.name)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .frame(height: 56)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                Text(option.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glyph-option.\(option.name)")
        .accessibilityLabel(option.label)
    }
}

/// The "No symbol" cell: clears the chosen glyph back to the kind-derived one.
private struct GlyphClearCell: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    Image(systemName: "slash.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 56)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                Text("None")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glyph-option-none")
        .accessibilityLabel("No symbol")
    }
}

/// The curated **colour picker** (CONTEXT.md → Action color; issue #243): the glyph
/// picker's sibling — the same grid, the same leading clear cell — offering the closed
/// `ActionColor` palette plus a **Default** row that restores the kind-derived tint.
/// No search: ten named swatches are a glance, not a lookup, so the searchable
/// furniture the glyph gallery needs would only get in the way here.
private struct ActionColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    /// The definition's chosen colour — written on selection, cleared by "Default".
    @Binding var selection: ActionColor?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                // The reset leads, as in the glyph picker: "back to the derived tint" is
                // always the first, thumb-reachable choice.
                ActionColorCell(
                    swatch: nil,
                    isSelected: selection == nil,
                    identifier: "action-color-option-default"
                ) {
                    selection = nil
                    dismiss()
                }
                ForEach(ActionColor.allCases, id: \.rawValue) { color in
                    ActionColorCell(
                        swatch: color,
                        isSelected: color == selection,
                        identifier: "action-color-option.\(color.rawValue)"
                    ) {
                        selection = color
                        dismiss()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The small colour chip the editor's Color row wears: the chosen token's fill, or the
/// neutral "no choice" slash for Default. Sized and cornered like a `ProviderBadge` so
/// the two rows line up, but deliberately *not* a badge — it previews the colour alone.
private struct ActionColorSwatch: View {
    let color: ActionColor?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color?.swiftUIColor ?? Color.secondary.opacity(0.18))
            .frame(width: 30, height: 30)
            .overlay {
                if color == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
    }
}

/// One swatch cell: the colour as the badge will actually fill it — with the same white
/// checkmark the badge draws its symbol in, so the cell previews the real legibility
/// rather than a bare colour chip. `swatch: nil` is the Default cell, which shows the
/// neutral "no choice" slash — and, when selected, the same checkmark in the secondary
/// ink its slash uses, so Default signals selection exactly as the ten colours do.
private struct ActionColorCell: View {
    let swatch: ActionColor?
    let isSelected: Bool
    let identifier: String
    let onTap: () -> Void

    /// The cell's caption — derived, never passed: a token always shows its own label,
    /// and the clear cell is always "Default", so the two can't be given inconsistently.
    private var label: String { swatch?.label ?? "Default" }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(swatch?.swiftUIColor ?? Color.secondary.opacity(0.12))
                    if swatch != nil {
                        // White-on-fill, exactly as the badge renders — so a swatch that
                        // couldn't hold a white glyph would be visibly wrong right here.
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: isSelected ? "checkmark" : "slash.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 56)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
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
