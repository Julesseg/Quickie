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
        .staticLink(id: id, title: title, url: URL(string: "https://\(id).example")!)
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

    @Test("a Fallback stays pinned to the bottom even when favorited")
    func favoritedFallbackStaysBottom() {
        // Fallbacks ride the bottom region regardless of signals — they're
        // reached by always being present, not by rank (issue #9 AC #4).
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("match", "Search Repo"), .webSearch()])],
            favorites: ["builtin.web-search"]
        )
        let ids = engine.results(for: "search").map(\.id)
        #expect(ids.first == "match")
        #expect(ids.last == "builtin.web-search")
    }
}
