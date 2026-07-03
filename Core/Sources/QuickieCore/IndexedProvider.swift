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

    /// The configurable kind this catalog belongs to (issue #67), so the kind's
    /// Enabled toggle governs it. `nil` — the default — for the catalogs that
    /// are no disableable kind: the built-in command rows.
    public let id: ProviderID?

    public init(catalog: [Action], weight: Double = 1.0, id: ProviderID? = nil) {
        self.catalog = catalog
        self.weight = weight
        self.id = id
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
    /// web-search Custom Action is seeded into the store as ordinary, deletable
    /// data (ADR 0021), not here. The Notes/Snippets library commands are wired
    /// alongside their stored content in the app.
    ///
    /// "Search Files" rides here too (CONTEXT.md → Search Files context; ADR 0014):
    /// it is a command row that enters the scoped file-browsing context, indexed
    /// beside the management commands so it matches by name like everything else —
    /// distinct from "Indexed Folders", which only manages *access* to the folders.
    public static func builtIns() -> IndexedProvider {
        IndexedProvider(catalog: [
            .openSettings(),
            .openQuicklinksPage(),
            .openFallbacksPage(),
            .searchFiles(),
            // The Settings command rows of the providers that never had a typed
            // management row (ADR 0019; issue #66): the dynamic injectors
            // (Calculator, File Search) and the capture providers (Events,
            // Reminders — whose "New …" rows start captures, not pages). With
            // these, every provider is reachable by typing its name.
            .openCalculatorPage(),
            .openFileSearchPage(),
            .openEventsPage(),
            .openRemindersPage(),
            // The Pile's settings command row (issue #67): its typed "Pile" row
            // opens the *entries* page (the ADR 0018 carve-out), so this is the
            // typed route to its Enabled toggle — riding the built-ins like the
            // rows above, it survives the Pile's own disable.
            .openPileSettings(),
        ])
    }
}
