import Foundation

/// A Provider whose Actions are a known, enumerable set, pre-indexed for fuzzy
/// search and re-indexed only when its underlying data changes (ADR 0004). In
/// the walking skeleton its catalog is a fixed set of built-in Actions; later
/// slices feed it Snippets, Quicklinks, Shortcuts, and favorites loaded from
/// the SwiftData store.
public struct IndexedProvider: Provider {
    public let kind: ProviderKind = .indexed

    /// This provider's match-score multiplier (issue #9 AC #3). `1.0` (neutral)
    /// unless a caller deliberately lifts or lowers a source — e.g. ranking the
    /// user's own Quicklinks above the shipped built-ins.
    public let weight: Double

    /// The full, enumerable set of Actions this provider indexes.
    public let catalog: [Action]

    public init(catalog: [Action], weight: Double = 1.0) {
        self.catalog = catalog
        self.weight = weight
    }

    /// Returns the whole catalog: an indexed provider does not filter, it
    /// enumerates. The SearchEngine matches and ranks.
    public func candidates(for query: String) -> [Action] {
        catalog
    }
}

extension IndexedProvider {
    /// The built-in command rows the app always indexes (CONTEXT.md → Management
    /// page): Settings, Quicklinks, Fallbacks, and Indexed Folders, each reached by
    /// typing its name to surface a full-screen page in place of chrome. Quickie
    /// ships **no** default Quicklinks and no privileged web search — the default
    /// web-search Fallback query is seeded into the store as ordinary, deletable
    /// data (ADR 0013), not here. The Notes/Snippets library commands are wired
    /// alongside their stored content in the app.
    public static func builtIns() -> IndexedProvider {
        IndexedProvider(catalog: [
            .openSettings(),
            .openQuicklinksPage(),
            .openFallbacksPage(),
            .openIndexedFoldersPage(),
        ])
    }
}
