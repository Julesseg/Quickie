import Foundation

/// A user-authored **Custom Action** definition (CONTEXT.md → Custom Action; ADR
/// 0021): a pure value describing a URL template whose `{name}` slots become the
/// breadcrumb's ordered, typed Arguments, and which factories a standard `Action`
/// whose final commit percent-encodes each value into its slot(s) and opens the
/// URL. It absorbs the retired Fallback query wholesale — web search is just a
/// default-seeded one-Argument, fallback-flagged instance.
///
/// This slice is **text-only**: every detected slot is a free-`text` Argument, in
/// URL-appearance order. The per-argument type/format/fill-order config the ADR
/// describes is the next slice; the type stays the seam it plugs into.
/// One live-detected argument **row** in the Custom Action editor (ADR 0021, issue
/// #94): a URL token `name` — the handle a rename rewrites — plus the `label` shown
/// for it (a numeric token auto-labels). A plain value the editor renders in fill
/// order; the app's view-model adds the SwiftUI controls around it.
public struct ArgumentRow: Equatable, Sendable, Identifiable {
    public let name: String
    public let label: String

    public init(name: String, label: String) {
        self.name = name
        self.label = label
    }

    /// Identity for `ForEach` is the token name — a rename produces a new row, and a
    /// duplicate name already collapsed to one row upstream, so names are unique here.
    public var id: String { name }
}

public struct CustomActionDefinition: Equatable, Sendable {
    /// The name shown in the Result row and matched against the query.
    public var name: String
    /// Alternative names also matched against the query.
    public var aliases: [String]
    /// The URL template — a stored URL carrying at least one `{name}` token the
    /// breadcrumb fills (a definition with no token factories no Action).
    public var template: String
    /// The **fill order** (CONTEXT.md → Custom Action; ADR 0021, issue #94): the
    /// token names in the order the breadcrumb asks them, which need not be the
    /// URL's own order. It is a *stored* order that can lag the live template —
    /// `orderedTokenNames` reconciles it hard against the tokens on every read, so a
    /// user's drag survives later template edits. Empty (the default) means
    /// URL-appearance order; the fields are `var` so the type doubles as the editor's
    /// live view-model surface.
    public var fillOrder: [String]
    /// The per-slot **type config** (ADR 0021, issue #96), keyed by token name so it
    /// survives a reorder or a rename (which re-keys it). A token absent here is a
    /// plain free-`text` slot (the default `ArgumentSpec`); a token the template lost
    /// is ignored on read and pruned by `reconciledSpecs` — the same hard mirror the
    /// rows follow, so a deleted slot drops its config with no stashing.
    public var argumentSpecs: [String: ArgumentSpec]
    /// The user-chosen **leading glyph** (CONTEXT.md → Custom Action; issue #163): an
    /// SF Symbol name picked from the curated `CustomActionGlyphCatalog` in the editor,
    /// which `makeAction` stamps onto the produced `Action.glyph` so it replaces the
    /// kind-derived leading glyph on every surface. `nil` (the default) leaves the
    /// derived glyph unchanged — a pure opt-in, so an action with no chosen symbol
    /// looks exactly as before. `var` so it doubles as the editor's live view-model
    /// surface, like the other fields.
    public var glyph: String?

    public init(
        name: String,
        aliases: [String] = [],
        template: String,
        fillOrder: [String] = [],
        argumentSpecs: [String: ArgumentSpec] = [:],
        glyph: String? = nil
    ) {
        self.name = name
        self.aliases = aliases
        self.template = template
        self.fillOrder = fillOrder
        self.argumentSpecs = argumentSpecs
        self.glyph = glyph
    }

    /// The distinct `{name}` token names in **URL-appearance order** — the raw slots
    /// the template declares. The same name appearing twice collapses to one entry
    /// (one Argument fills every occurrence); numeric names (`{1}`) are accepted like
    /// any other. An empty `{}` pair is not a token. This is the template's own order;
    /// the breadcrumb's asking order is `orderedTokenNames` (fill order).
    public var tokenNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        var searchStart = template.startIndex
        while let range = template.range(
            of: "\\{[^}]+\\}",
            options: .regularExpression,
            range: searchStart..<template.endIndex
        ) {
            let name = String(template[range].dropFirst().dropLast())
            if seen.insert(name).inserted { names.append(name) }
            searchStart = range.upperBound
        }
        return names
    }

    /// The token names in **fill order** — the breadcrumb's asking order — reconciled
    /// hard against the live template (ADR 0021, issue #94). Surviving names keep
    /// their stored fill-order position; tokens the template gained since (not in
    /// `fillOrder`) append in URL-appearance order; names the template lost drop
    /// immediately, no stashing. An empty stored order therefore defaults to
    /// URL-appearance order, and a drag persists across later template edits.
    public var orderedTokenNames: [String] {
        Self.reconcile(order: fillOrder, tokens: tokenNames)
    }

    /// Reconciles a stored fill order against the template's live tokens (the pure
    /// hard-mirror rule): survivors first in their stored order, then any new tokens
    /// in URL-appearance order, dropping vanished names. **Deduped** — one row per
    /// live token, matching `tokenNames` — so a corrupt or legacy fill order carrying
    /// a repeated name can never render two rows for one slot.
    static func reconcile(order: [String], tokens: [String]) -> [String] {
        let live = Set(tokens)
        var seen = Set<String>()
        var result: [String] = []
        for name in order where live.contains(name) && seen.insert(name).inserted {
            result.append(name)
        }
        for token in tokens where seen.insert(token).inserted { result.append(token) }
        return result
    }

    /// The live-detected argument **rows** the editor renders beneath the URL field,
    /// in fill order (ADR 0021, issue #94). Each row pairs the URL `name` (the token
    /// a rename rewrites) with the `label` shown for it — a purely numeric token
    /// (`{1}`), a positional placeholder with no meaning, auto-labels until renamed.
    public var rows: [ArgumentRow] {
        orderedTokenNames.map { ArgumentRow(name: $0, label: Self.autoLabel(for: $0)) }
    }

    /// The display label for a token: the name itself, unless the name is **purely
    /// numeric** (`{1}`, `{2}`) — a positional placeholder — in which case it
    /// auto-labels as "Argument N" until the user renames it (ADR 0021, issue #94).
    static func autoLabel(for name: String) -> String {
        (!name.isEmpty && name.allSatisfy(\.isNumber)) ? "Argument \(name)" : name
    }

    /// The spec for a token — its stored config or a default free-`text` spec when
    /// the token has none. The single read point so an absent spec always resolves
    /// to the same default.
    func spec(for name: String) -> ArgumentSpec {
        argumentSpecs[name] ?? ArgumentSpec()
    }

    /// The ordered, typed Arguments the breadcrumb collects — one per distinct token
    /// in **fill order**, each typed by its sidecar `ArgumentSpec` (issue #96):
    /// `number` and `date` carry that content type, a `choice` carries its inline
    /// options (so its input method is the fuzzy list), and everything else is free
    /// text. Labelled per `rows`; empty when the template carries no token.
    public var arguments: [Argument] {
        rows.map { row in
            let spec = spec(for: row.name)
            switch spec.type {
            case .text:
                return Argument(label: row.label, contentType: .text)
            case .number:
                return Argument(label: row.label, contentType: .number)
            case .date:
                // The format's meaning fixes whether the picker collects a time
                // (issue #96) — no in-picker toggle for a Custom Action date slot.
                return Argument(label: row.label, contentType: .date, dateIncludesTime: spec.dateIncludesTime)
            case .choice:
                return Argument(label: row.label, contentType: .text, options: spec.effectiveOptions)
            }
        }
    }

    /// The argument specs pruned to the live tokens (ADR 0021, issue #96): a token
    /// the template lost drops its config, matching the hard mirror the rows follow.
    /// The form the editor persists.
    public var reconciledSpecs: [String: ArgumentSpec] {
        let live = Set(tokenNames)
        return argumentSpecs.filter { live.contains($0.key) }
    }

    // MARK: - Editor operations (pure, mutating the view-model surface)

    /// Reorders the argument rows to set the **fill order** — the breadcrumb's asking
    /// order — leaving the URL template untouched (ADR 0021, issue #94). The offsets
    /// index into the current `orderedTokenNames`, matching a SwiftUI `.onMove`. The
    /// reconciled order is baked into `fillOrder` so the drag persists across later
    /// template edits.
    public mutating func moveArguments(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        fillOrder = Self.moved(orderedTokenNames, fromOffsets: offsets, toOffset: destination)
    }

    /// The stdlib-only equivalent of SwiftUI's `Array.move(fromOffsets:toOffset:)`
    /// (which Core can't import): the moved elements are lifted out, then reinserted
    /// at `destination` adjusted for those removed before it — matching `.onMove`'s
    /// semantics so the editor and this pure function agree.
    static func moved<T>(_ array: [T], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [T] {
        let moving = offsets.sorted().map { array[$0] }
        var result = array
        for index in offsets.sorted(by: >) { result.remove(at: index) }
        let insertAt = destination - offsets.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: insertAt)
        return result
    }

    /// Renames the argument whose URL token is `old` to `new`, **rewriting the token
    /// in the template** in place — every occurrence, keeping a duplicated slot's
    /// fan-out — so the name link between form row and URL stays intact without
    /// hand-editing (ADR 0021, issue #94). The row keeps its fill-order slot. A no-op
    /// when `old` isn't a live token.
    /// Renames the argument at fill-order position `index` — the editor's live,
    /// per-keystroke rename (issue #94 follow-up). Binding a row's text field to this
    /// by *position* (rather than by the token name, which changes on every keystroke
    /// and would drop focus) lets the URL token track the field as it is typed. Guards
    /// are `renameArgument`'s: a no-op on an out-of-range index, an empty name (which
    /// would collapse the token to an invalid `{}` and drop the row mid-edit), or a
    /// collision with another live token.
    public mutating func setArgumentName(at index: Int, to new: String) {
        let names = orderedTokenNames
        guard names.indices.contains(index) else { return }
        renameArgument(names[index], to: new)
    }

    /// The spec for the argument at fill-order position `index` — the editor reads
    /// this to render a row's type picker and per-type fields (issue #96). An
    /// out-of-range index resolves to the default free-`text` spec.
    public func spec(at index: Int) -> ArgumentSpec {
        let names = orderedTokenNames
        guard names.indices.contains(index) else { return ArgumentSpec() }
        return spec(for: names[index])
    }

    /// Writes the spec for the argument at fill-order position `index`, keyed by its
    /// live token name so it tracks the row (issue #96). The editor binds a row's
    /// controls to this by position, matching `setArgumentName`. A no-op out of range.
    public mutating func setSpec(at index: Int, to spec: ArgumentSpec) {
        let names = orderedTokenNames
        guard names.indices.contains(index) else { return }
        argumentSpecs[names[index]] = spec
    }

    /// Sets just the **type** of the argument at fill-order position `index`, leaving
    /// its other config intact — the row's type picker (issue #96).
    public mutating func setArgumentType(at index: Int, to type: ArgumentType) {
        var updated = spec(at: index)
        updated.type = type
        setSpec(at: index, to: updated)
    }

    public mutating func renameArgument(_ old: String, to new: String) {
        // No-op unless `old` is a live token being renamed to a genuinely different,
        // non-empty name that doesn't already belong to *another* live token. An empty
        // name would rewrite the token to an invalid `{}` and drop the row; renaming
        // onto a live name would merge two arguments into one (`tokenNames` dedupes the
        // rewritten template but the fill order wouldn't, so the breadcrumb would keep
        // two rows while the fill wrote the first answer into both slots and silently
        // dropped the second). Rejecting both keeps rows and fill in step.
        guard old != new, !new.isEmpty, tokenNames.contains(old), !tokenNames.contains(new) else { return }
        // Rename within the resolved fill order first — against the still-current
        // template — so the row keeps its slot; then rewrite the URL token. Doing it
        // the other way drops `old` before the order is captured, sending the renamed
        // row to the end.
        fillOrder = orderedTokenNames.map { $0 == old ? new : $0 }
        template = template.replacingOccurrences(of: "{\(old)}", with: "{\(new)}")
        // Re-key the sidecar config so a slot's type/options/formats follow the
        // rename rather than reverting to a default free-text slot (issue #96).
        if let spec = argumentSpecs.removeValue(forKey: old) { argumentSpecs[new] = spec }
    }

    /// Factories the standard `Action` this definition drives (ADR 0021, 0030). A
    /// Custom Action is a URL with **zero or more** slots, and the slot count picks
    /// the shape:
    ///
    /// - **Zero slots** — a *static* Custom Action (the former Quicklink; ADR 0030):
    ///   its URL is already resolved, so it opens directly on a bare `run(input:)`,
    ///   wears the `.quicklink` leading glyph, and declares `.quicklink(id:)` content
    ///   so its long-press menu carries copy/share **and** Edit. It is not
    ///   fallback-eligible (nothing to seed a query into).
    /// - **One or more slots** — the breadcrumb-filled Custom Action: its `arguments`
    ///   feed the `MultiStepAction` engine and its multi-step effect fills the
    ///   collected values into the template as an `openURL` outcome. Its single-step
    ///   `effect` is a placeholder (`.none`) — it always runs through the breadcrumb,
    ///   verb-first (empty) or fallback seed-and-commit, exactly as a Shortcut Action
    ///   that accepts input — and it declares `.customAction(id:)` content (Edit alone,
    ///   since its URL only exists once the slots are filled).
    ///
    /// Returns `nil` only when a zero-slot template does not parse as a URL — a
    /// slot-less string the Save gate would already have rejected.
    public func makeAction(id: String) -> Action? {
        let names = orderedTokenNames
        guard !names.isEmpty else {
            // A static (slot-less) Custom Action: the resolved URL opens directly.
            guard let url = URL(string: template) else { return nil }
            return Action(
                id: id,
                kind: .quicklink,
                title: name,
                aliases: aliases,
                inputTypes: [],
                outputType: .url,
                content: .quicklink(id: id),
                glyph: normalizedGlyph
            ) { _ in .openURL(url) }
        }
        let template = self.template
        let arguments = self.arguments
        // The specs aligned to `names` (fill order) — the same order the breadcrumb
        // collects `values` in — so `fill` serializes each value with its own slot's
        // type/format config (issue #96).
        let specs = names.map { spec(for: $0) }
        return Action(
            id: id,
            kind: .customAction,
            title: name,
            aliases: aliases,
            inputTypes: [.text],
            outputType: .url,
            arguments: arguments,
            // A Custom Action declares `.customAction(id:)` content (ADR 0017): its
            // URL only exists once the slots are filled, so — like a Shortcut — it
            // carries no pre-resolved value to copy or share, but the id lets the
            // long-press menu add **Edit** (open the live-mirroring editor on the
            // stored record). Without the id it would read as `.none` and expose only
            // the universal Copy action deeplink.
            content: .customAction(id: id),
            glyph: normalizedGlyph,
            effect: { _ in .none },
            multiStepEffect: { values in
                CustomActionDefinition.fill(template: template, tokenNames: names, specs: specs, values: values)
            }
        )
    }

    /// The chosen glyph normalized to *set* vs *unset* (issue #163): a blank or
    /// whitespace-only name collapses to `nil` so an "empty" glyph reads as unset (the
    /// derived glyph applies) rather than an unrenderable blank symbol. The single
    /// point the raw stored value becomes the leading-glyph override — `makeAction`
    /// stamps it onto the Action, and the editor reads it so its "None" label can't
    /// drift from what the surfaces actually render.
    public var normalizedGlyph: String? {
        Self.normalizedGlyph(glyph)
    }

    /// Normalizes a raw stored glyph string to *set* vs *unset* — the shared rule the
    /// instance property and the App's management-page badge both read, so a
    /// whitespace-only value reads as "no symbol" everywhere identically.
    public static func normalizedGlyph(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return raw
    }

    /// The `ActionKind` the produced Action wears, derived from **shape** (issue #163):
    /// a slotted template is a `.customAction`, a slot-less one a static `.quicklink`
    /// (the split `makeAction` applies). The single source of truth the editor's badge
    /// preview and the management-page row share, so the shape→kind mapping — and the
    /// tint it selects — never drifts across surfaces.
    public var derivedKind: ActionKind {
        Self.derivedKind(forTemplate: template)
    }

    /// The `ActionKind` a Custom Action with this URL template wears — exposed as a
    /// static so a surface holding only a raw `urlString` (the management-page row)
    /// resolves the same kind without rebuilding a definition.
    public static func derivedKind(forTemplate template: String) -> ActionKind {
        Action.templateContainsPlaceholder(template) ? .customAction : .quicklink
    }

    // MARK: - Save validation (the editor is the validator; ADR 0021, issue #94)

    /// Whether the name is non-empty after trimming — the first Save gate.
    public var nameIsValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the template carries at least one `{name}` slot. Not a Save gate any
    /// more (ADR 0030 — a slot-less URL is a valid *static* Custom Action): the editor
    /// reads it to decide whether to show the Argument rows and the fallback note,
    /// both of which apply only to a slotted action.
    public var hasSlot: Bool { !tokenNames.isEmpty }

    /// Whether the template parses as a URL **with a scheme** once every slot is
    /// filled with a probe value (ADR 0021): the real validation of "opens
    /// somewhere". Probing avoids rejecting a well-formed template whose bare `{name}`
    /// happens to make the raw string unparseable, and requiring a scheme rejects a
    /// query-only or plain-text template that could never open an app or the browser.
    public var urlIsSchemedAfterProbe: Bool {
        var probed = template
        for name in tokenNames {
            probed = probed.replacingOccurrences(of: "{\(name)}", with: "x")
        }
        guard let url = URL(string: probed), let scheme = url.scheme, !scheme.isEmpty else {
            return false
        }
        return true
    }

    /// Whether the produced Action is **fallback-eligible** — derived from shape, not
    /// declared (CONTEXT.md → Fallback Action; the retired fallback flag): its first
    /// argument *by fill order* must be free text, so the seeded query has somewhere
    /// to land. It keys off the first fill-order token's declared **type**, so a
    /// number/date/choice first argument makes it ineligible (issue #96) — a choice
    /// slot's content type is also `.text`, so checking the spec type rather than the
    /// derived content type is what makes the gate bite. The editor shows this as an
    /// informational note (no toggle); it mirrors `Action.isFallbackEligible`, the
    /// runtime source of truth.
    public var isFallbackEligible: Bool {
        guard let first = orderedTokenNames.first else { return false }
        return spec(for: first).type == .text
    }

    /// Whether every `choice` slot carries at least one non-blank option (ADR 0021,
    /// issue #96) — the added Save gate, since a choice with no options presents an
    /// empty runtime list the user could never get past.
    public var choiceOptionsAreValid: Bool {
        orderedTokenNames.allSatisfy { name in
            let spec = spec(for: name)
            return spec.type != .choice || !spec.effectiveOptions.isEmpty
        }
    }

    /// Whether the definition may be **saved** (ADR 0021, 0030): a non-empty name, a
    /// schemed URL after probe substitution, and non-empty options for every choice
    /// slot. The **slot count may be zero** — a slot-less schemed URL is a valid
    /// *static* Custom Action (the former Quicklink), so `hasSlot` no longer gates
    /// Save. Fallback eligibility likewise never gates Save — it is derived from shape,
    /// so a text-first slotted action simply becomes eligible for the Fallback list's
    /// pool while a static link is ineligible. The runtime keeps its silent no-op on
    /// the can't-happen fill failure; this predicate is what makes that unreachable.
    public var isValidForSave: Bool {
        nameIsValid && urlIsSchemedAfterProbe && choiceOptionsAreValid
    }

    /// The characters a filled **value** may carry unescaped: `.urlQueryAllowed`
    /// minus the sub-delimiters that are *structural* in a query — `&` (separates
    /// params), `=` (separates key from value), `+` (a space under form decoding),
    /// and `#` (starts the fragment). A multi-slot template splices values into a
    /// structured query (`?title={title}&notes={notes}`), so a title of "Milk & eggs"
    /// left with a raw `&` would be read as a delimiter — truncating the title and
    /// injecting a bogus parameter. Escaping these per-value keeps each value inside
    /// its own slot. `$` and the other query-legal characters stay unescaped, so
    /// "$5 menu" keeps its "$5" (a stricter `.alphanumerics` would over-encode).
    private static let valueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#")
        return set
    }()

    /// Fills the collected Argument values into the template (ADR 0021): each token
    /// occurrence is replaced **literally** by the percent-encoded value — no regex
    /// replacement template, where `$1`/`\` would be read as capture references. A
    /// repeated name fills every occurrence from its one Argument; a value missing
    /// from `values` (only the glyph-probe `run(arguments: [])` passes fewer) fills
    /// empty. The encoding escapes the structural query delimiters (`valueAllowed`),
    /// so a value can never break out of its slot, and can never contain `{`/`}`
    /// (both escaped), so no replacement introduces a new token or collides across
    /// names. The template's own delimiters stay literal — only the value is encoded.
    static func fill(
        template: String,
        tokenNames: [String],
        specs: [ArgumentSpec] = [],
        values: [ArgumentValue]
    ) -> ActionOutcome {
        var filled = template
        for (index, name) in tokenNames.enumerated() {
            let raw: String
            if index < values.count {
                let spec = index < specs.count ? specs[index] : ArgumentSpec()
                raw = rawValue(values[index], spec: spec)
            } else {
                raw = ""
            }
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? raw
            filled = filled.replacingOccurrences(of: "{\(name)}", with: encoded)
        }
        guard let url = URL(string: filled) else { return .none }
        return .openURL(url)
    }

    /// The raw (pre-encoding) string one collected value fills its slot with, by kind
    /// (issue #96): free text and a number both fill their literal text; a choice
    /// fills the **chosen label** (id = label); a date serializes to its ISO default
    /// — `yyyy-MM-dd` date-only or `yyyy-MM-dd'T'HH:mm` timed, branched on whether the
    /// user included a time — unless the slot's spec overrides that branch's format.
    static func rawValue(_ value: ArgumentValue, spec: ArgumentSpec) -> String {
        switch value {
        case .text(let text):
            return text
        case .choice(let option):
            return option.label
        case .date(let date, let hasTime):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = spec.outputFormat(hasTime: hasTime)
            return formatter.string(from: date)
        }
    }
}
