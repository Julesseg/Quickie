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

    private let effect: @Sendable (String?) -> ActionOutcome

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        inputTypes: [ContentType] = [],
        outputType: ContentType,
        effect: @escaping @Sendable (String?) -> ActionOutcome
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.inputTypes = inputTypes
        self.outputType = outputType
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
    /// A static Quicklink: a fixed URL that opens directly, consuming no input
    /// (CONTEXT.md → Quicklink with no placeholder). The bread-and-butter of
    /// the built-in Indexed Provider in the skeleton.
    public static func staticLink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        url: URL
    ) -> Action {
        Action(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            inputTypes: [],
            outputType: .url
        ) { _ in .openURL(url) }
    }

    /// A placeholder-Quicklink: a URL template with a single `{query}` token
    /// the typed text fills (CONTEXT.md → Quicklink, Fallback Action). The
    /// foundation for the built-in web-search fallback.
    public static func placeholderLink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        template: String
    ) -> Action {
        Action(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            inputTypes: [.text],
            outputType: .url
        ) { input in
            let raw = input ?? ""
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            let filled = template.replacingOccurrences(of: "{query}", with: encoded)
            guard let url = URL(string: filled) else { return .none }
            return .openURL(url)
        }
    }
}
