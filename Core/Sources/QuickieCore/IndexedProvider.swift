import Foundation

/// A Provider whose Actions are a known, enumerable set, pre-indexed for fuzzy
/// search and re-indexed only when its underlying data changes (ADR 0004). In
/// the walking skeleton its catalog is a fixed set of built-in Actions; later
/// slices feed it Snippets, Quicklinks, Shortcuts, and favorites loaded from
/// the SwiftData store.
public struct IndexedProvider: Provider {
    public let kind: ProviderKind = .indexed

    /// The full, enumerable set of Actions this provider indexes.
    public let catalog: [Action]

    public init(catalog: [Action]) {
        self.catalog = catalog
    }

    /// Returns the whole catalog: an indexed provider does not filter, it
    /// enumerates. The SearchEngine matches and ranks.
    public func candidates(for query: String) -> [Action] {
        catalog
    }
}

extension IndexedProvider {
    /// The handful of built-in Actions the skeleton ships so the loop has
    /// something to match against on first launch, before the user has added
    /// any Quicklinks or Snippets of their own. The web-search Fallback's engine
    /// is configurable — the app passes the user's persisted template so the
    /// default search engine stays editable (issue #5, AC #6).
    public static func builtIns(
        webSearchTemplate: String = "https://duckduckgo.com/?q={query}"
    ) -> IndexedProvider {
        IndexedProvider(catalog: [
            .staticLink(
                id: "builtin.github",
                title: "Open GitHub",
                aliases: ["git"],
                url: URL(string: "https://github.com")!
            ),
            .staticLink(
                id: "builtin.apple",
                title: "Open Apple",
                url: URL(string: "https://apple.com")!
            ),
            .staticLink(
                id: "builtin.wikipedia",
                title: "Open Wikipedia",
                aliases: ["wiki"],
                url: URL(string: "https://wikipedia.org")!
            ),
            .webSearch(template: webSearchTemplate),
        ])
    }
}
