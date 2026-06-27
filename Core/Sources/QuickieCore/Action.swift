import Foundation

/// What running an Action's main action *means*, as a value the platform layer
/// performs. The core stays pure — it never opens a URL or touches the
/// pasteboard itself — so the loop (match → rank → run) is fully testable
/// without UIKit. The SwiftUI app interprets the outcome (`openURL` →
/// `UIApplication.open`, `copyText` → `UIPasteboard`).
public enum ActionOutcome: Equatable, Sendable {
    case openURL(URL)
    case copyText(String)
    case none
}

/// A single invokable capability shown in the Result list — the one kind of
/// thing in the index. Every subsystem (matcher, ranking, providers) operates
/// on Actions. An Action declares its typed input/output content (ADR 0011)
/// and carries a *main action*: the effect tapping its row performs, exposed
/// as `run(input:)`.
public struct Action: Identifiable, Sendable {
    public let id: String
    /// The name shown in the row and matched against the query.
    public let title: String
    public let subtitle: String?
    /// Alternative names also matched against the query.
    public let aliases: [String]
    /// Content type(s) this Action consumes (empty for a self-contained link).
    public let inputTypes: [ContentType]
    /// The content type this Action produces.
    public let outputType: ContentType
    /// Whether this Action is a Fallback: always surfaced in the Result list,
    /// pinned in the bottom fallback region, consuming the raw typed text rather
    /// than matching by name (CONTEXT.md → Fallback Action).
    public let isFallback: Bool

    private let effect: @Sendable (String?) -> ActionOutcome

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        inputTypes: [ContentType] = [],
        outputType: ContentType,
        isFallback: Bool = false,
        effect: @escaping @Sendable (String?) -> ActionOutcome
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.inputTypes = inputTypes
        self.outputType = outputType
        self.isFallback = isFallback
        self.effect = effect
    }

    /// Runs the main action. `input` is the raw typed text for Actions that
    /// consume it (Fallbacks/placeholder-Quicklinks); self-contained Actions
    /// ignore it.
    public func run(input: String? = nil) -> ActionOutcome {
        effect(input)
    }
}

extension Action {
    /// A Quicklink built from a single stored URL *template* (CONTEXT.md →
    /// Quicklink). The one field drives both shapes: a template with a
    /// `{placeholder}` token takes the typed text as its Argument and
    /// substitutes it (consuming `.text`); a template with none opens directly
    /// (consuming nothing). This is the auto-detecting model the SwiftData store
    /// persists and the manage UI edits — no static/placeholder mode toggle.
    public static func quicklink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        template: String,
        isFallback: Bool = false
    ) -> Action {
        let hasPlaceholder = templateHasPlaceholder(template)
        return Action(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            inputTypes: hasPlaceholder ? [.text] : [],
            outputType: .url,
            isFallback: isFallback
        ) { input in
            fill(template: template, with: input)
        }
    }

    /// True when `template` carries at least one `{placeholder}` token — the
    /// signal that the Quicklink takes an Argument rather than opening directly.
    /// Exposed so the app's editor can mirror the same static-vs-placeholder
    /// detection the factory uses (issue #5).
    public static func templateHasPlaceholder(_ template: String) -> Bool {
        template.range(of: "\\{[^}]+\\}", options: .regularExpression) != nil
    }

    /// Substitutes the typed text into every `{placeholder}` token (M1's single
    /// Argument fills them all), percent-encoding it for the query string. A
    /// template with no placeholder ignores `input` and opens as stored.
    ///
    /// The substitution is *literal*: each `{…}` token is matched, then replaced
    /// with the encoded text as a plain string. We never feed the typed text to
    /// a regex replacement template, where `$1`/`\` would be read as capture
    /// references — `.urlQueryAllowed` leaves `$` unescaped, so "$5 menu" would
    /// otherwise lose its "$5".
    private static func fill(template: String, with input: String?) -> ActionOutcome {
        let raw = input ?? ""
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw

        // Replace one token at a time, re-scanning from the start. This
        // terminates because the encoded text can never contain `{`/`}` (both
        // are escaped by `.urlQueryAllowed`), so each pass strictly removes one
        // token and never introduces a new one.
        var filled = template
        while let token = filled.range(of: "\\{[^}]+\\}", options: .regularExpression) {
            filled.replaceSubrange(token, with: encoded)
        }

        guard let url = URL(string: filled) else { return .none }
        return .openURL(url)
    }

    /// A static Quicklink: a fixed URL that opens directly, consuming no input
    /// (CONTEXT.md → Quicklink with no placeholder). A convenience over
    /// `quicklink` for callers that already hold a parsed `URL` (the built-in
    /// Indexed Provider). A placeholder-free URL routes through the same
    /// substitution path, so it simply opens as stored.
    public static func staticLink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        url: URL
    ) -> Action {
        quicklink(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            template: url.absoluteString
        )
    }

    /// The built-in web-search Fallback (CONTEXT.md → Fallback Action): a
    /// placeholder-Quicklink, flagged a Fallback, that consumes the raw typed
    /// text. The search engine *is* the template, so swapping engines is just
    /// passing a different one — "the default search engine is editable." The
    /// app persists the chosen template and passes it here.
    public static func webSearch(
        template: String = "https://duckduckgo.com/?q={query}"
    ) -> Action {
        quicklink(
            id: "builtin.web-search",
            title: "Search the web",
            aliases: ["search", "google", "ddg"],
            template: template,
            isFallback: true
        )
    }

    /// A placeholder-Quicklink: a URL template with a `{placeholder}` token the
    /// typed text fills (CONTEXT.md → Quicklink, Fallback Action). A thin alias
    /// over `quicklink` for call sites that read better naming the placeholder
    /// intent explicitly; both share one substitution path.
    public static func placeholderLink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        template: String,
        isFallback: Bool = false
    ) -> Action {
        quicklink(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            template: template,
            isFallback: isFallback
        )
    }
}
