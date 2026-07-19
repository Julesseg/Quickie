import Foundation

/// The **ranked-dynamic** Provider for File Search (CONTEXT.md → File Search; ADR
/// 0015). Unlike an Indexed Provider — whose whole catalog the SearchEngine
/// enumerates and ranks centrally — File Search **owns its own filename snapshot
/// and prefilters it itself**, so a set of tens of thousands of filenames never
/// floods the central catalog, Home, or Frecency.
///
/// Its handful of survivors are then scored by the same `Matcher` the rest of the
/// loop uses and gated two ways so only solid hits appear inline while typing a
/// normal query:
/// - the **substring threshold** (`Matcher.substringMatchThreshold`, ADR 0035):
///   a filename *containing* the query — exact, prefix, or buried substring —
///   surfaces inline; a scattered or typo hit is held back (it surfaces only in
///   the uncapped Search Files context, ADR 0014),
/// - an **inline cap** (~3 rows): even among qualifying matches, only the best
///   few surface while typing.
///
/// This is *ranked*-dynamic, not the Calculator's *boosted*-dynamic: the
/// SearchEngine routes these survivors through name-scoring into the ranked region
/// rather than floating them to the top, so an exact command name still outranks a
/// strong filename hit (see `SearchEngine.results`). Every result carries only its
/// `(bookmarkID, relativePath)` — the Core never touches the filesystem.
public struct FileSearchProvider: Provider {
    public let kind: ProviderKind = .rankedDynamic

    /// File Search is a configurable kind (issue #67): its Enabled toggle
    /// governs the inline file rows, though its typed settings command row
    /// rides the built-ins and stays.
    public let id: ProviderID? = .fileSearch

    /// The in-memory filename snapshot, built by the app under a per-folder
    /// security-scoped bracket and rebuilt on launch / foreground / grant change.
    /// Every keystroke is served from this snapshot — never a filesystem rescan.
    private let index: FilenameIndex

    /// The active keyboard layout, so typo-forgiveness matches the rest of the
    /// loop; defaults to QWERTY so the Core stays platform-agnostic and testable.
    private let layout: KeyboardLayout

    /// How many qualifying file matches may surface inline while typing a normal
    /// query (~3, ADR 0015). The Search Files context is uncapped.
    private let inlineCap: Int

    /// Builds the provider over `index`, dropping every entry under a
    /// **disabled** Indexed Folder up front (issue #68 follow-up): the one
    /// filter covers both the inline `candidates(for:)` path and the Search
    /// Files context, so a disabled folder's files are hidden from every
    /// surface — reversibly, since the grant and the snapshot are untouched.
    /// `disabledFolders` holds grant ids (`FileEntry.bookmarkID`s).
    public init(
        index: FilenameIndex,
        layout: KeyboardLayout = .qwerty,
        inlineCap: Int = 3,
        disabledFolders: Set<String> = []
    ) {
        self.index = disabledFolders.isEmpty
            ? index
            : FilenameIndex(entries: index.entries.filter { !disabledFolders.contains($0.bookmarkID) })
        self.layout = layout
        self.inlineCap = inlineCap
    }

    /// The file Actions for `query`: prefilter the snapshot, score the survivors,
    /// keep only contiguous (substring-or-better) matches, order best-first, and
    /// cap the inline count. An empty/whitespace query declines cleanly — File
    /// Search never adds a spurious row, and the empty-query Home state is owned
    /// by the SearchEngine.
    public func candidates(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scored: [(entry: FileEntry, score: Double)] = index
            .prefiltered(for: trimmed)
            .compactMap { entry in
                guard let score = Matcher.score(query: trimmed, candidate: entry.displayName, layout: layout),
                      score >= Matcher.substringMatchThreshold else { return nil }
                return (entry, score)
            }
            .sorted(by: bestFirst)

        return scored.prefix(inlineCap).map { action(for: $0.entry) }
    }

    /// The file Actions for the **Search Files context** (CONTEXT.md → Search Files
    /// context; ADR 0014): the uncapped, ungated counterpart to `candidates(for:)`.
    /// The scoped file-browsing surface shows *every* filename match, not just the
    /// contiguous ones the inline path allows, and never caps the count — so a
    /// scattered or typo hit the root list holds back still appears here. An empty/whitespace
    /// query **browses everything**, ordered by name, so entering the context lists
    /// the whole file set before the user has typed a filter.
    public func contextMatches(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return index.entries
                .sorted(by: byName)
                .map(action(for:))
        }

        return index
            .prefiltered(for: trimmed)
            .compactMap { entry in
                guard let score = Matcher.score(query: trimmed, candidate: entry.displayName, layout: layout) else { return nil }
                return (entry, score)
            }
            .sorted(by: bestFirst)
            .map { action(for: $0.entry) }
    }

    /// The Search Files context matches as **rows** — each file Action plus its Match
    /// highlight (CONTEXT.md → Match highlight; issue #195), so the scoped surface
    /// bolds a filename hit identically to the inline rows the engine returns. A file
    /// has no aliases, so its title always wins the match; the browse-all (empty
    /// query) list carries no highlight, since nothing was matched. Region is
    /// `.ranked`: a file row is a name-scored survivor, never boosted or a fallback.
    public func contextRows(for query: String) -> [ResultRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return contextMatches(for: query).map { action in
            let match = trimmed.isEmpty
                ? nil
                : MatchHighlight.titleMatch(query: trimmed, title: action.title, layout: layout)
            return ResultRow(action: action, region: .ranked, match: match)
        }
    }

    /// Builds the file Action for an entry — the one place the provider projects a
    /// `FileEntry` into a row, so the inline and context paths agree on identity.
    private func action(for entry: FileEntry) -> Action {
        Action.file(
            bookmarkID: entry.bookmarkID,
            relativePath: entry.relativePath,
            displayName: entry.displayName
        )
    }

    /// Orders two entries for the browse-all (empty-query) context list: by display
    /// name, then relative path, so the untyped file set reads in a stable order.
    private func byName(_ lhs: FileEntry, _ rhs: FileEntry) -> Bool {
        if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
        return lhs.relativePath < rhs.relativePath
    }

    /// Orders two scored survivors best-first: higher score wins, then a
    /// deterministic tie-break on display name and relative path so equal-scoring
    /// files never reshuffle between runs.
    private func bestFirst(_ lhs: (entry: FileEntry, score: Double), _ rhs: (entry: FileEntry, score: Double)) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.entry.displayName != rhs.entry.displayName { return lhs.entry.displayName < rhs.entry.displayName }
        return lhs.entry.relativePath < rhs.entry.relativePath
    }
}
