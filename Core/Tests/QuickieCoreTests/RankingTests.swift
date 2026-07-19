import Foundation
import Testing
@testable import QuickieCore

// The ranking blend (issue #9 AC #3, #4): on top of the raw match score, Results
// fold in the user's signals — Favorites, Frecency, and provider weight — while
// keeping the structural guarantees the list depends on: exact/prefix name
// matches float to the top, and Fallbacks stay pinned to the bottom region.
//
// Each test pits two Actions that tie on raw match score, so only the signal
// under test can break the tie — which is exactly what the blend must do.
struct RankingTests {

    private func link(_ id: String, _ title: String) -> Action {
        .quicklink(id: id, title: title, url: URL(string: "https://\(id).example")!)
    }

    @Test("a favorited Action outranks an equally-matched non-favorite")
    func favoriteBoostsRanking() {
        // Identical titles tie on match score; without a boost the deterministic
        // tie-break orders by id, putting "a-plain" first.
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a-plain", "Repo"), link("b-fav", "Repo")])],
            favorites: ["b-fav"]
        )
        #expect(engine.results(for: "repo").map(\.id) == ["b-fav", "a-plain"])
    }

    @Test("a recently-selected Action outranks an equally-matched cold one")
    func frecencyBoostsRanking() {
        let now = Date()
        var frecency = Frecency()
        frecency.record("b-warm", at: now)
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a-plain", "Repo"), link("b-warm", "Repo")])],
            frecency: frecency,
            now: now
        )
        #expect(engine.results(for: "repo").map(\.id) == ["b-warm", "a-plain"])
    }

    @Test("an Action from a higher-weight provider outranks an equal match from a default one")
    func providerWeightBoostsRanking() {
        let engine = SearchEngine(providers: [
            IndexedProvider(catalog: [link("a-plain", "Repo")]),
            IndexedProvider(catalog: [link("b-heavy", "Repo")], weight: 1.5),
        ])
        #expect(engine.results(for: "repo").map(\.id) == ["b-heavy", "a-plain"])
    }

    @Test("an exact/prefix match floats above a favorited weak match")
    func exactFloatsAboveBoostedWeakMatch() {
        // "git" is an exact hit on "git" (top tier) but only a buried substring
        // of "legit" (weak). Even with a Favorite boost on the weak one, the
        // exact match must stay on top — the boost reorders within a tier, never
        // across it (issue #9 AC #4).
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("exact", "git"), link("buried", "legit")])],
            favorites: ["buried"]
        )
        #expect(engine.results(for: "git").map(\.id).first == "exact")
    }

    @Test("a Fallback's region row stays pinned to the bottom even when favorited")
    func favoritedFallbackRegionStaysBottom() {
        // The bottom fallback region rides below the name-matches regardless of
        // signals — it's reached by always being present, not by rank (issue #9
        // AC #4), so the favorite boost never lifts the *region* row out of it.
        // A query that doesn't name-match the fallback surfaces it only there.
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("match", "Search Repo"), .webSearchFallback()])],
            favorites: ["builtin.web-search"],
            enabledFallbacks: [Action.webSearchFallbackID]
        )
        let ids = engine.results(for: "repo").map(\.id)
        #expect(ids.first == "match")
        #expect(ids.last == "builtin.web-search")
        // "repo" hits "Search Repo" but not "Search the web", so the fallback rides
        // the region only — no ranked duplicate.
        #expect(ids.filter { $0 == "builtin.web-search" }.count == 1)
    }

    @Test("a favorited Fallback's ranked duplicate ranks by its blended score")
    func favoritedFallbackRankedDuplicateFloats() {
        // When the query *does* name-match the fallback, the dual-row rule surfaces a
        // ranked duplicate too (issue #197), and that row ranks like any name match:
        // here the favorite boost floats the favorited web-search's duplicate above the
        // unfavorited "Search Repo". The region row is still pinned to the very bottom.
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("match", "Search Repo"), .webSearchFallback()])],
            favorites: ["builtin.web-search"],
            enabledFallbacks: [Action.webSearchFallbackID]
        )
        let ids = engine.results(for: "search").map(\.id)
        #expect(ids.first == "builtin.web-search")  // favorited ranked duplicate
        #expect(ids.last == "builtin.web-search")   // region row, always bottom
        #expect(ids.filter { $0 == "builtin.web-search" }.count == 2)
    }
}
