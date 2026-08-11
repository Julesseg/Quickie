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
                AppearancePickerView(def: $def, kind: previewKind)
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
        } footer: {
            Text("Give this action its own symbol and color, shown everywhere it appears. Leave them as None and Default to use the ones its kind provides.")
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

/// The merged **Symbol & Color page** (CONTEXT.md → Custom Action, Action color;
/// issues #163, #243) — one pushed page for the whole appearance, replacing the two
/// separate pickers this editor used to offer.
///
/// The hero is the **composed result**: the same `ProviderBadge` every surface draws,
/// at the same proportions, restyling live as you tap. That is the point of merging
/// them — a symbol and a colour are only ever seen together, so choosing them apart
/// meant judging each against an imagined version of the other. Here the answer to
/// "how will this look?" is on screen the whole time.
///
/// The hero and the colour row are **pinned**; only the glyph gallery scrolls. A hero
/// that scrolled away would be a preview you cannot see while making the choice it
/// previews. Back confirms — there is no auto-dismiss on tap, so a wrong tap is
/// corrected by tapping again rather than by re-opening the page.
private struct AppearancePickerView: View {
    @Binding var def: CustomActionDefinition
    /// The kind the badge composes over — the shape-derived tint behind a Default
    /// colour, so the hero matches what the action will actually wear.
    let kind: ActionKind

    /// The glyph gallery's fuzzy query, ranked by the same `Matcher` furniture the
    /// choice input method uses, so the gallery reads best-match-first exactly as a
    /// breadcrumb choice step does.
    @State private var query = ""

    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
    private let glyphColumns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    /// The curated options ranked by the shared fuzzy matcher — best first.
    private var results: [GlyphOption] {
        CustomActionGlyphCatalog.search(query)
    }

    /// The hue the page echoes: the chosen colour, else the kind's own tint. Resolved
    /// through the shared rule so the gallery's selection never disagrees with the hero.
    private var tint: Color {
        resolvedActionTint(kind: kind, color: def.color)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: glyphColumns, spacing: 10) {
                // The reset leads its group, as it did in the picker this replaces:
                // "back to the derived glyph" is never buried behind a scroll.
                glyphCell(nil, symbol: "slash.circle", label: "No symbol",
                          identifier: "glyph-option-none")
                ForEach(results) { option in
                    glyphCell(option.name, symbol: option.name, label: option.label,
                              identifier: "glyph-option.\(option.name)")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 40)

            if results.isEmpty {
                Text("No symbols match “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        // Pinned, not scrolled: the preview has to stay put while the gallery moves
        // under it. A `safeAreaInset` (rather than a VStack + nested ScrollView) keeps
        // the gallery a real scroll view, so it still gets scroll-to-top, keyboard
        // dismissal, and correct safe-area insets.
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("Symbol & Color")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The pinned half: the live hero, its caption, and the colour row.
    private var header: some View {
        VStack(spacing: 14) {
            // The badge at the size the app draws it, scaled up as one piece — so the
            // corner radius, glyph weight, and gradient stay in the proportions every
            // surface uses instead of being re-specified (and drifting) here.
            ProviderBadge(kind: kind, symbol: def.normalizedGlyph, color: def.color)
                .scaleEffect(2.6, anchor: .center)
                .frame(width: 78, height: 78)
                .animation(.snappy(duration: 0.18), value: def.color)
                .animation(.snappy(duration: 0.18), value: def.normalizedGlyph)
                .accessibilityIdentifier("appearance-hero")

            Text(heroCaption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            LazyVGrid(columns: colorColumns, spacing: 12) {
                colorCircle(nil)
                ForEach(ActionColor.allCases, id: \.rawValue) { color in
                    colorCircle(color)
                }
            }
            .padding(.horizontal)

            searchField
                .padding(.horizontal)
                .padding(.top, 2)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        // An opaque backdrop so the gallery scrolls *under* the pinned header rather
        // than showing through it.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The gallery's filter, sitting at the **bottom** of the pinned header — directly
    /// above the thing it filters. An inline field rather than `.searchable`'s nav-bar
    /// drawer: the drawer would sit above the *hero*, detaching the control from the
    /// grid it acts on and pushing the preview down the screen.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search symbols", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("glyph-search-field")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("glyph-search-clear")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }

    /// What the hero is currently made of, spelled out — the colour's name, and the
    /// symbol's when one is chosen. The caption carries the names so the swatches and
    /// glyph cells don't each need a label crowding the grid.
    private var heroCaption: String {
        let color = def.color?.label ?? "Default"
        guard let glyph = def.normalizedGlyph,
              let option = CustomActionGlyphCatalog.all.first(where: { $0.name == glyph })
        else { return color }
        return "\(option.label) · \(color)"
    }

    private func colorCircle(_ color: ActionColor?) -> some View {
        Button {
            def.color = color
        } label: {
            ZStack {
                Circle()
                    .fill(color?.swiftUIColor ?? Color.secondary.opacity(0.15))
                if color == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .overlay {
                if def.color == color {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .frame(width: 46, height: 46)
                }
            }
            // A 48pt square around a 38pt circle: the ring needs the room, and the tap
            // target should not be the circle alone.
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(color.map { "action-color-option.\($0.rawValue)" } ?? "action-color-option-default")
        .accessibilityLabel(color?.label ?? "Default")
        .accessibilityAddTraits(def.color == color ? [.isButton, .isSelected] : .isButton)
    }

    /// One gallery cell. The selected one is tinted with the **current colour choice**,
    /// not the app accent, so the gallery echoes the hero instead of introducing a third
    /// colour that means nothing here.
    private func glyphCell(_ value: String?, symbol: String, label: String, identifier: String) -> some View {
        let isSelected = def.normalizedGlyph == value
        return Button {
            def.glyph = value
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.22) : Color.secondary.opacity(0.10))
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? tint : (value == nil ? Color.secondary : .primary))
            }
            .frame(height: 46)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
