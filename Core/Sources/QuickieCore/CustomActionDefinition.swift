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
public struct CustomActionDefinition: Equatable, Sendable {
    /// The name shown in the Result row and matched against the query.
    public let name: String
    /// Alternative names also matched against the query.
    public let aliases: [String]
    /// The URL template — a stored URL carrying at least one `{name}` token the
    /// breadcrumb fills (a definition with no token factories no Action).
    public let template: String
    /// Whether this is a **Fallback** Action (CONTEXT.md → Fallback Action): always
    /// surfaced in the bottom region, its selection seeding the typed query as
    /// Argument 1. Orthogonal to being a Custom Action — it is still startable
    /// verb-first, where the breadcrumb begins empty.
    public let isFallback: Bool

    public init(
        name: String,
        aliases: [String] = [],
        template: String,
        isFallback: Bool = false
    ) {
        self.name = name
        self.aliases = aliases
        self.template = template
        self.isFallback = isFallback
    }

    /// The distinct `{name}` token names in **URL-appearance order** — the ordered
    /// slots the breadcrumb collects. The same name appearing twice collapses to one
    /// entry (one Argument fills every occurrence); numeric names (`{1}`) are
    /// accepted like any other. An empty `{}` pair is not a token.
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

    /// The ordered, typed Arguments the breadcrumb collects — one free-`text`
    /// Argument per distinct token, labelled by the token name, in URL-appearance
    /// order (this slice is text-only). Empty when the template carries no token.
    public var arguments: [Argument] {
        tokenNames.map { Argument(label: $0, contentType: .text) }
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
        let names = tokenNames
        guard !names.isEmpty else { return nil }
        let template = self.template
        return Action(
            id: id,
            kind: .customAction,
            title: name,
            aliases: aliases,
            inputTypes: [.text],
            outputType: .url,
            isFallback: isFallback,
            arguments: names.map { Argument(label: $0, contentType: .text) },
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

    /// Fills the collected Argument values into the template (ADR 0021): each token
    /// occurrence is replaced **literally** by the percent-encoded (`.urlQueryAllowed`)
    /// value — no regex replacement template, where `$1`/`\` would be read as capture
    /// references (`.urlQueryAllowed` leaves `$` unescaped, so "$5 menu" keeps its
    /// "$5"). A repeated name fills every occurrence from its one Argument; a value
    /// missing from `values` (only the glyph-probe `run(arguments: [])` passes fewer)
    /// fills empty. The encoded value can never contain `{`/`}` (both are escaped),
    /// so no replacement can introduce a new token or collide across names.
    static func fill(template: String, tokenNames: [String], values: [ArgumentValue]) -> ActionOutcome {
        var filled = template
        for (index, name) in tokenNames.enumerated() {
            let raw: String
            if index < values.count, case .text(let text) = values[index] { raw = text } else { raw = "" }
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            filled = filled.replacingOccurrences(of: "{\(name)}", with: encoded)
        }
        guard let url = URL(string: filled) else { return .none }
        return .openURL(url)
    }
}
