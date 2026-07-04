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
    /// Whether this is a **Fallback** Action (CONTEXT.md → Fallback Action): always
    /// surfaced in the bottom region, its selection seeding the typed query as
    /// Argument 1. Orthogonal to being a Custom Action — it is still startable
    /// verb-first, where the breadcrumb begins empty.
    public var isFallback: Bool
    /// The **fill order** (CONTEXT.md → Custom Action; ADR 0021, issue #94): the
    /// token names in the order the breadcrumb asks them, which need not be the
    /// URL's own order. It is a *stored* order that can lag the live template —
    /// `orderedTokenNames` reconciles it hard against the tokens on every read, so a
    /// user's drag survives later template edits. Empty (the default) means
    /// URL-appearance order; the fields are `var` so the type doubles as the editor's
    /// live view-model surface.
    public var fillOrder: [String]

    public init(
        name: String,
        aliases: [String] = [],
        template: String,
        isFallback: Bool = false,
        fillOrder: [String] = []
    ) {
        self.name = name
        self.aliases = aliases
        self.template = template
        self.isFallback = isFallback
        self.fillOrder = fillOrder
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

    /// The ordered, typed Arguments the breadcrumb collects — one free-`text`
    /// Argument per distinct token in **fill order** (this slice is text-only),
    /// labelled per `rows`. Empty when the template carries no token.
    public var arguments: [Argument] {
        rows.map { Argument(label: $0.label, contentType: .text) }
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
    public mutating func renameArgument(_ old: String, to new: String) {
        // No-op unless `old` is a live token being renamed to a genuinely different
        // name that doesn't already belong to *another* live token. Renaming onto a
        // live name would merge two arguments into one: `tokenNames` dedupes the
        // rewritten template but the fill order wouldn't, so the breadcrumb would keep
        // two rows while the fill wrote the first answer into both slots and silently
        // dropped the second. Rejecting the collision keeps rows and fill in step.
        guard old != new, tokenNames.contains(old), !tokenNames.contains(new) else { return }
        // Rename within the resolved fill order first — against the still-current
        // template — so the row keeps its slot; then rewrite the URL token. Doing it
        // the other way drops `old` before the order is captured, sending the renamed
        // row to the end.
        fillOrder = orderedTokenNames.map { $0 == old ? new : $0 }
        template = template.replacingOccurrences(of: "{\(old)}", with: "{\(new)}")
    }

    /// Factories the standard `Action` this definition drives (ADR 0021): its
    /// `arguments` feed the existing `MultiStepAction` engine and its multi-step
    /// effect fills the collected values into the template as an `openURL` outcome —
    /// no new outcome case. Returns `nil` when the template carries no `{name}`
    /// token, the type's defining invariant, so a static link can never masquerade
    /// as one.
    ///
    /// The single-step `effect` is a placeholder (`.none`): a Custom Action always
    /// runs through the breadcrumb — verb-first (empty) or fallback seed-and-commit
    /// — never a bare `run(input:)`, exactly as a Shortcut Action that accepts input.
    public func makeAction(id: String) -> Action? {
        let names = orderedTokenNames
        guard !names.isEmpty else { return nil }
        let template = self.template
        let arguments = self.arguments
        return Action(
            id: id,
            kind: .customAction,
            title: name,
            aliases: aliases,
            inputTypes: [.text],
            outputType: .url,
            isFallback: isFallback,
            arguments: arguments,
            // A Custom Action is a hand-off whose URL only exists once the slots are
            // filled, so — like a Shortcut — it carries no pre-resolved value to copy
            // or share: `.none` content, no secondary actions.
            content: ResultContent.none,
            effect: { _ in .none },
            multiStepEffect: { values in
                CustomActionDefinition.fill(template: template, tokenNames: names, values: values)
            }
        )
    }

    // MARK: - Save validation (the editor is the validator; ADR 0021, issue #94)

    /// Whether the name is non-empty after trimming — the first Save gate.
    public var nameIsValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the template carries at least one `{name}` slot. A slot-less URL is
    /// not a Custom Action (it consumes nothing) — the editor gently redirects it
    /// toward a Quicklink rather than saving it (ADR 0021).
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

    /// Whether the **fallback flag** may be set: the first argument *by fill order*
    /// must be free text, so the seeded query has somewhere to land (ADR 0021). This
    /// slice is text-only, so it is true whenever there is a first argument — but it
    /// keys off `arguments` (fill order), so it stays correct once argument types
    /// land and a date/choice-first action can't be flagged.
    public var canBeFallback: Bool {
        arguments.first?.contentType == .text
    }

    /// Whether the definition may be **saved** (ADR 0021): a non-empty name, at least
    /// one slot, a schemed URL after probe substitution, and — if the fallback flag is
    /// on — a free-text first argument. The runtime keeps its silent no-op on the
    /// can't-happen fill failure; this predicate is what makes that unreachable.
    public var isValidForSave: Bool {
        nameIsValid && hasSlot && urlIsSchemedAfterProbe && (!isFallback || canBeFallback)
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
    static func fill(template: String, tokenNames: [String], values: [ArgumentValue]) -> ActionOutcome {
        var filled = template
        for (index, name) in tokenNames.enumerated() {
            let raw: String
            if index < values.count, case .text(let text) = values[index] { raw = text } else { raw = "" }
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? raw
            filled = filled.replacingOccurrences(of: "{\(name)}", with: encoded)
        }
        guard let url = URL(string: filled) else { return .none }
        return .openURL(url)
    }
}
