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

    /// The user's single **enabled Fallback list**, most-important-first (CONTEXT.md
    /// → Fallback list) — the *only* persisted fallback fact. An id's position both
    /// admits it to the bottom region and decides where it rides; the disabled pool
    /// is everything eligible but absent here, derived, never stored. A `[String: Int]`
    /// rank map keyed by id for O(1) membership and ordering.
    private let enabledRank: [String: Int]

    /// The kind-level Enabled switches (CONTEXT.md → Disabled; issue #67): a
    /// disabled provider contributes nothing to typed results, the Frecency
    /// "Recent" list, or the Favorites grid — reversibly, its data retained.
    private let enablement: ProviderEnablement

    /// The **instance**-level Disabled state (CONTEXT.md → Disabled; issue
    /// #68): single actions — a Quicklink, Snippet, Pile entry, or Shortcut —
    /// reversibly hidden by stable id from results, Recents, and Favorites,
    /// while staying in their Management page's Actions list. A disabled kind
    /// short-circuits its instances (the provider is skipped before any id is
    /// consulted); `resolvableHomeIDs()` ignores this set like it ignores the
    /// kinds, so a disabled favorite keeps its pin. Instance-disabling a fallback
    /// hides its row here yet leaves its rank in `enabledFallbacks` intact, so
    /// re-enabling restores it to the same position (the Favorites keep-the-pin
    /// precedent; issue #114).
    private let disabledInstances: Set<String>

    /// The boost a Favorite adds to its match score. Tuned to reorder *within* a
    /// match tier (e.g. float a pinned exact match above an unpinned one)
    /// without lifting a weak match over a clean exact/prefix one — the tiers,
    /// not the boost, own that guarantee.
    private static let favoriteBoost = 0.5

    /// The match score at or above which a name match counts as exact/prefix and
    /// floats to the top tier (issue #9 AC #4) — the one shared threshold
    /// (`Matcher.strongMatchThreshold`, 0.80) so the engine's tier boundary and
    /// File Search's inline gate can never drift.
    private static let strongMatchThreshold = Matcher.strongMatchThreshold

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
        enabledFallbacks: [String] = [],
        enablement: ProviderEnablement = ProviderEnablement(),
        disabledInstances: Set<String> = []
    ) {
        self.providers = providers
        self.layout = layout
        self.favoriteOrder = favorites
        self.favorites = Set(favorites)
        self.frecency = frecency
        self.now = now
        var rank: [String: Int] = [:]
        for (index, id) in enabledFallbacks.enumerated() where rank[id] == nil { rank[id] = index }
        self.enabledRank = rank
        self.enablement = enablement
        self.disabledInstances = disabledInstances
    }

    /// Whether a Provider's Actions may surface at all (issue #67): true unless
    /// the provider declares a kind the user has switched off. A kind-less
    /// provider (the built-in command rows) is always live — that is what keeps
    /// every Settings command row typeable while its provider is disabled.
    private func isLive(_ provider: Provider) -> Bool {
        provider.id.map(enablement.isEnabled) ?? true
    }

    /// The ranked Result list for `query`, best match first. An empty or
    /// whitespace-only query returns `[]` — the signal for the app to show the
    /// Home placeholder rather than a Result list.
    public func results(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Sort each Provider's candidates into the three regions of the Result
        // list (ADR 0008, ADR 0015), preserving the provider order the App wired.
        // A candidate's region is decided by *how* it earns its place: a Fallback
        // is pinned bottom; a **boosted**-dynamic result (Calculator) is a
        // type-triggered hit that floats top unscored; everything else — an
        // Indexed catalog entry *or* a **ranked**-dynamic survivor (File Search) —
        // is name-scored and ranked by the blend (match score + favorite +
        // frecency + provider weight), so an exact command name still outranks a
        // strong filename hit.
        var boosted: [Action] = []  // boosted-dynamic: type-triggered, floats top
        var ranked: [Ranked] = []   // indexed + ranked-dynamic: scored + blended
        var fallbacks: [Action] = [] // pinned to the bottom region
        for provider in providers where isLive(provider) {
            let weight: Double = provider.weight
            for action in provider.candidates(for: trimmed) {
                // A disabled instance is reversibly hidden from results while
                // staying in its Management page's Actions list (issue #68).
                // Checked after the kind gate, so a disabled kind
                // short-circuits its instances regardless of per-instance
                // state.
                guard !disabledInstances.contains(action.id) else { continue }
                if action.isFallbackEligible, enabledRank[action.id] != nil {
                    // Eligible *and* in the user's enabled list → it rides the
                    // bottom region (CONTEXT.md → Fallback list). The Fallbacks
                    // kind's Enabled toggle is the *master* switch over the whole
                    // region (issue #67): the enabled list spans three kinds
                    // (Custom Actions + Save for later + New Snippet), and a
                    // disabled kind short-circuits its instances (CONTEXT.md →
                    // Disabled) — even the two permanent captures that ride other
                    // providers' catalogs. Master off drops the row entirely.
                    // An eligible action *not* in the enabled list falls through to
                    // name-matching below: a pooled Custom Action / Shortcut is
                    // still startable verb-first.
                    if enablement.isEnabled(.fallbacks) { fallbacks.append(action) }
                } else if provider.kind == .dynamic {
                    // Boosted-dynamic results skip name-matching — the Provider
                    // already decided they apply (Provider.swift: "boosted-dynamic
                    // … already query-relevant").
                    boosted.append(action)
                } else if let raw = bestScore(for: action, query: trimmed) {
                    // Indexed or ranked-dynamic: name-matched and dropped when the
                    // query misses. A File Search survivor lands here so its match
                    // quality — not its provider — decides where it ranks.
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
    /// signals (issue #9 AC #1, #2). Only **Indexed** Actions are eligible: Home
    /// is the enumerable catalog of things to pin and reuse, not the query-driven
    /// Dynamic results. A fallback-eligible Indexed Action (a text-first Custom
    /// Action, Save for later, New Snippet) is part of that catalog: pinning it
    /// draws a card that launches it verb-first. An action currently riding the
    /// fallback region stays out of the **Recent** list, though — it already sits at
    /// the bottom of every Result list, so auto-surfacing it again would only be noise.
    ///
    /// - Parameter showRecents: the app-level **Show Recents** toggle
    ///   (CONTEXT.md → Settings; issue #65), default on. Off empties the Frecency
    ///   "Recent" section while leaving Favorites untouched — the signals keep
    ///   recording and ranking; only the Home surface is hidden.
    public func home(showRecents: Bool = true) -> HomeContent {
        // Disabled kinds are excluded here (issue #67): their Favorites drop
        // from the grid — without consuming a visible slot, since the pin list
        // itself is untouched — and their Frecency rows leave the Recent list.
        let byId = indexedActionsByID(includingDisabled: false)

        let favorites: [Action] = favoriteOrder.compactMap { byId[$0] }

        var frecent: [Action] = []
        if showRecents {
            for id in frecency.ranked(now: now) where !self.favorites.contains(id) {
                // An action currently riding the fallback region stays out of the
                // Recent list — it already sits at the bottom of every Result list,
                // so auto-surfacing it again would only be noise. A pooled eligible
                // action isn't in the region, so it recents like any other Action.
                if let action = byId[id], !isEnabledFallback(action) { frecent.append(action) }
            }
        }

        return HomeContent(favorites: favorites, frecent: frecent)
    }

    /// Whether an Action currently rides the bottom fallback region — eligible by
    /// shape *and* present in the user's enabled list. The one predicate `results`,
    /// `home`, and `indexedActionsByID` share so a fallback's "is it active?" answer
    /// can never drift between the Result list and Home. A pooled eligible action is
    /// not enabled, so it reads as a normal Action everywhere.
    private func isEnabledFallback(_ action: Action) -> Bool {
        action.isFallbackEligible && enabledRank[action.id] != nil
    }

    /// The Indexed Actions keyed by id — the enumerable catalog `home()` resolves
    /// Favorite and Frecency ids against, fallback entries included (a pinned
    /// fallback draws a card like any other pin). `home()` reads it with disabled
    /// kinds *and* disabled instances excluded, so their cards and Recent rows
    /// vanish; an enabled fallback additionally honours the Fallbacks master switch,
    /// mirroring `results(for:)`. `resolvableHomeIDs()` reads it unfiltered, because
    /// a disabled action still *exists* — only a deleted one stops resolving.
    private func indexedActionsByID(includingDisabled: Bool) -> [String: Action] {
        var byId: [String: Action] = [:]
        for provider in providers where provider.kind == .indexed {
            guard includingDisabled || isLive(provider) else { continue }
            for action in provider.candidates(for: "") {
                if !includingDisabled {
                    if disabledInstances.contains(action.id) { continue }
                    // An enabled fallback hidden by the master switch draws no card,
                    // like any disabled kind. A pooled eligible action isn't riding
                    // the region, so it keeps its card.
                    if isEnabledFallback(action), !enablement.isEnabled(.fallbacks) { continue }
                }
                if byId[action.id] == nil { byId[action.id] = action }
            }
        }
        return byId
    }

    /// The ids of every Indexed Action currently in the catalog — fallbacks
    /// included — exactly the set a Favorite or Frecency id can resolve to on
    /// Home. The App reconciles persisted Favorites against this so an id whose
    /// target no longer exists (a deleted Snippet, or a stale id from an older
    /// build) is pruned rather than lingering invisibly and consuming a
    /// Favorites slot.
    ///
    /// Deliberately ignores enablement at both levels (issue #67 AC #3, issue
    /// #68): a disabled Favorite — whether its kind or the single instance was
    /// switched off — keeps its pin, dropped from the grid by `home()` and
    /// restored on re-enable, so it must keep resolving here or the
    /// reconciliation would prune the pin the moment it was disabled.
    public func resolvableHomeIDs() -> Set<String> {
        Set(indexedActionsByID(includingDisabled: true).keys)
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

    /// Orders the bottom fallback region by the user's enabled-list order, read
    /// most-important-first (CONTEXT.md → Fallback list): an id's position places it
    /// nearest the ranked matches (the thumb). Every region member carries a rank
    /// (membership *is* being in the enabled list), so the ranks always decide; the
    /// title/id tie-break is a defensive fallthrough that keeps results stable if two
    /// ids ever share a position.
    private func orderFallbacks(_ lhs: Action, _ rhs: Action) -> Bool {
        let lRank = enabledRank[lhs.id]
        let rRank = enabledRank[rhs.id]
        if lRank != rRank {
            switch (lRank, rRank) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
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
