import Foundation

/// Turns a typed query into the ranked Result list — the loop minus the pixels.
/// It gathers candidate Actions from every Provider, scores each against the
/// query via the `Matcher` (best of title or aliases), drops non-matches, and
/// sorts best-first so the top row sits nearest the input.
///
/// Ranking blends the match score with the user's signals — Favorites, Frecency,
/// and provider weight (issue #9) — while preserving two structural guarantees:
/// exact/prefix name matches float to a top tier no boost can cross, and
/// Fallbacks stay pinned to the bottom region. The same providers and signals
/// also compose the empty-query `home()` state (Favorites row + Frecency list).
public struct SearchEngine {
    private let providers: [Provider]
    /// The active keyboard layout, used by the Matcher to weight adjacent-key
    /// typos. The App keeps this in step with `UITextInputMode`; the Core
    /// defaults to QWERTY so it stays platform-agnostic and testable.
    private let layout: KeyboardLayout
    /// Ids of the user's pinned Favorites, in pin order — the order Home renders
    /// the Favorites row in (CONTEXT.md → Favorite; issue #9 AC #1).
    private let favoriteOrder: [String]
    /// The same Favorites as a Set for O(1) membership during scoring (issue #9
    /// AC #3).
    private let favorites: Set<String>
    /// The user's frequency × recency signal — a ranking boost on top of match
    /// score (CONTEXT.md → Frecency; issue #9 AC #3). Empty by default so the
    /// skeleton's matcher-only ranking is unchanged until selections accrue.
    private let frecency: Frecency
    /// The instant the frecency decay is evaluated against. Injected (defaulting
    /// to now) so ranking is deterministic under test; the App passes the current
    /// time each time it rebuilds the engine.
    private let now: Date

    /// The user's explicit Fallback list order, most-important-first (CONTEXT.md
    /// → Fallback list): fallback ids whose position decides where each rides in
    /// the bottom region. A `[String: Int]` rank map for O(1) lookup; a fallback
    /// absent from it sorts after every ordered one, deterministically.
    private let fallbackRank: [String: Int]
    /// Fallback ids the user has **disabled** (CONTEXT.md → Fallback list): kept
    /// in the list but never surfaced in results.
    private let disabledFallbacks: Set<String>

    /// The boost a Favorite adds to its match score. Tuned to reorder *within* a
    /// match tier (e.g. float a pinned exact match above an unpinned one)
    /// without lifting a weak match over a clean exact/prefix one — the tiers,
    /// not the boost, own that guarantee.
    private static let favoriteBoost = 0.5

    /// The match score at or above which a name match counts as exact/prefix and
    /// floats to the top tier (issue #9 AC #4). It is the Matcher's prefix base
    /// (0.80): exact (1.0) and prefix matches clear it, buried/scattered/fuzzy
    /// matches fall below it.
    private static let strongMatchThreshold = 0.80

    /// How much each unit of frecency score adds to a match. Kept modest so the
    /// signal nudges ordering within a tier rather than dominating the raw match
    /// quality — a habitually-used Action surfaces, but typing a different name
    /// still wins.
    private static let frecencyWeight = 0.3

    public init(
        providers: [Provider],
        layout: KeyboardLayout = .qwerty,
        favorites: [String] = [],
        frecency: Frecency = Frecency(),
        now: Date = Date(),
        fallbackOrder: [String] = [],
        disabledFallbacks: Set<String> = []
    ) {
        self.providers = providers
        self.layout = layout
        self.favoriteOrder = favorites
        self.favorites = Set(favorites)
        self.frecency = frecency
        self.now = now
        var rank: [String: Int] = [:]
        for (index, id) in fallbackOrder.enumerated() { rank[id] = index }
        self.fallbackRank = rank
        self.disabledFallbacks = disabledFallbacks
    }

    /// The ranked Result list for `query`, best match first. An empty or
    /// whitespace-only query returns `[]` — the signal for the app to show the
    /// Home placeholder rather than a Result list.
    public func results(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Sort each Provider's candidates into the three regions of the Result
        // list (ADR 0008), preserving the provider order the App wired. A
        // candidate's region is decided by *how* it earns its place: a Fallback
        // is pinned bottom; a Dynamic Provider's result is a type-triggered hit
        // that floats top; everything else is a verb-first name-match, ranked by
        // the blend (match score + favorite + frecency + provider weight).
        var boosted: [Action] = []  // type-triggered, already query-relevant
        var ranked: [Ranked] = []   // verb-first, scored + blended
        var fallbacks: [Action] = [] // pinned to the bottom region
        for provider in providers {
            let weight: Double = provider.weight
            for action in provider.candidates(for: trimmed) {
                if action.isFallback {
                    // A disabled fallback is kept in the user's list but never
                    // surfaced in results (CONTEXT.md → Fallback list).
                    if !disabledFallbacks.contains(action.id) { fallbacks.append(action) }
                } else if provider.kind == .dynamic {
                    // Dynamic results skip name-matching — the Provider already
                    // decided they apply (Provider.swift: "dynamic candidates
                    // arrive already query-relevant").
                    boosted.append(action)
                } else if let raw = bestScore(for: action, query: trimmed) {
                    // Verb-first: name-matched and dropped when the query misses.
                    let blended: Double = blend(raw: raw, weight: weight, id: action.id)
                    ranked.append(Ranked(action: action, raw: raw, blended: blended))
                }
            }
        }

        ranked.sort(by: rank)
        fallbacks.sort(by: orderFallbacks)

        return boosted + ranked.map(\.action) + fallbacks
    }

    /// The highlighted result for `query` — the single best row, `results[0]`,
    /// rendered nearest the input and the thumb (CONTEXT.md → Highlighted result).
    /// Pressing Enter runs exactly this row's main action; an empty/whitespace
    /// query returns `nil`, which is the no-op signal — on Home, Enter does
    /// nothing. A thin read over `results(for:)` so the selection rule lives in
    /// one place and can't drift from the list.
    public func highlighted(for query: String) -> Action? {
        results(for: query).first
    }

    /// The two sections of the empty-query Home state (CONTEXT.md → Home): the
    /// pinned Favorites row and the auto Frecency list. The App renders these
    /// when the query is empty — the same moment `results(for:)` returns `[]`.
    public struct HomeContent: Sendable {
        /// Pinned Favorites, in pin order — the tap-without-typing shortcuts.
        public let favorites: [Action]
        /// Recently/often-used Actions, best-first by frecency, excluding any
        /// already shown as a Favorite so the two sections never duplicate.
        public let frecent: [Action]
    }

    /// Builds the Home state from the engine's indexed Actions and the user's
    /// signals (issue #9 AC #1, #2). Only **Indexed**, non-Fallback Actions are
    /// eligible: Home is the enumerable catalog of things to pin and reuse, not
    /// the query-driven Dynamic results or the raw-text Fallbacks.
    public func home() -> HomeContent {
        var byId: [String: Action] = [:]
        for provider in providers where provider.kind == .indexed {
            for action in provider.candidates(for: "") where !action.isFallback {
                if byId[action.id] == nil { byId[action.id] = action }
            }
        }

        let favorites: [Action] = favoriteOrder.compactMap { byId[$0] }

        var frecent: [Action] = []
        for id in frecency.ranked(now: now) where !self.favorites.contains(id) {
            if let action = byId[id] { frecent.append(action) }
        }

        return HomeContent(favorites: favorites, frecent: frecent)
    }

    /// A scored match in flight: the raw matcher score (which fixes its tier)
    /// alongside the blended score the user's signals produce (which orders it
    /// within that tier).
    private struct Ranked {
        let action: Action
        let raw: Double
        let blended: Double
    }

    /// Folds the user's ranking signals into a raw match score (issue #9 AC #3):
    /// the Provider's weight scales the match, then a Favorite boost and the
    /// frecency score add on top. The result only ever reorders matches *within*
    /// a tier — `rank` keeps exact/prefix matches above weaker ones regardless.
    private func blend(raw: Double, weight: Double, id: String) -> Double {
        var score = raw * weight
        if favorites.contains(id) { score += Self.favoriteBoost }
        score += Self.frecencyWeight * frecency.score(for: id, now: now)
        return score
    }

    /// Orders two matches best-first. Exact/prefix matches form a top tier that
    /// always outranks weaker matches regardless of any boost (issue #9 AC #4);
    /// within a tier the blended score decides, then a deterministic tie-break on
    /// title and id so equal scores never reorder unpredictably between runs.
    private func rank(_ lhs: Ranked, _ rhs: Ranked) -> Bool {
        let lStrong = lhs.raw >= Self.strongMatchThreshold
        let rStrong = rhs.raw >= Self.strongMatchThreshold
        if lStrong != rStrong { return lStrong }
        if lhs.blended != rhs.blended { return lhs.blended > rhs.blended }
        if lhs.action.title != rhs.action.title { return lhs.action.title < rhs.action.title }
        return lhs.action.id < rhs.action.id
    }

    /// Orders the bottom fallback region by the user's explicit list order, read
    /// most-important-first (CONTEXT.md → Fallback list): a fallback's rank in the
    /// list places it nearest the ranked matches (the thumb). A fallback the user
    /// hasn't ordered yet (e.g. a freshly seeded one) sorts after every ordered
    /// one, then by title/id so the result list never reshuffles between runs.
    private func orderFallbacks(_ lhs: Action, _ rhs: Action) -> Bool {
        let lRank = fallbackRank[lhs.id]
        let rRank = fallbackRank[rhs.id]
        if lRank != rRank {
            switch (lRank, rRank) {
            case let (l?, r?): return l < r
            case (_?, nil): return true   // ordered before unordered
            case (nil, _?): return false
            case (nil, nil): break
            }
        }
        return lhs.title != rhs.title ? lhs.title < rhs.title : lhs.id < rhs.id
    }

    /// The best match score across an Action's title and its aliases — a query
    /// that hits any of an Action's names surfaces it.
    private func bestScore(for action: Action, query: String) -> Double? {
        ([action.title] + action.aliases)
            .compactMap { Matcher.score(query: query, candidate: $0, layout: layout) }
            .max()
    }
}
