import Foundation
import Testing
@testable import QuickieCore

// The empty-query Home state (CONTEXT.md → Home; issue #9 AC #1, #2): a row of
// pinned Favorites and an auto Frecency list of recently/often-used Actions.
// `home()` is the empty-query sibling of `results(for:)` — it composes those two
// sections from the same providers + signals the engine already holds.
struct HomeTests {

    private func link(_ id: String, _ title: String) -> Action {
        .staticLink(id: id, title: title, url: URL(string: "https://\(id).example")!)
    }

    @Test("Home lists the pinned Favorites in pin order")
    func favoritesInPinOrder() {
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a", "Alpha"), link("b", "Bravo"), link("c", "Charlie")])],
            favorites: ["c", "a"]
        )
        #expect(engine.home().favorites.map(\.id) == ["c", "a"])
    }

    @Test("Home's Frecency list is ordered most-used first")
    func frecencyListOrdered() {
        let now = Date()
        var frecency = Frecency()
        frecency.record("a", at: now)
        frecency.record("b", at: now)
        frecency.record("b", at: now) // "b" chosen more often
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a", "Alpha"), link("b", "Bravo")])],
            frecency: frecency,
            now: now
        )
        #expect(engine.home().frecent.map(\.id) == ["b", "a"])
    }

    @Test("a Favorite is not duplicated in the Frecency list")
    func favoriteNotDuplicatedInFrecency() {
        let now = Date()
        var frecency = Frecency()
        frecency.record("a", at: now)
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a", "Alpha")])],
            favorites: ["a"],
            frecency: frecency,
            now: now
        )
        #expect(engine.home().favorites.map(\.id) == ["a"])
        #expect(engine.home().frecent.isEmpty)
    }

    @Test("Fallbacks never appear on Home")
    func fallbacksExcludedFromHome() {
        let now = Date()
        var frecency = Frecency()
        frecency.record("builtin.web-search", at: now)
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [.webSearch()])],
            favorites: ["builtin.web-search"],
            frecency: frecency,
            now: now
        )
        #expect(engine.home().favorites.isEmpty)
        #expect(engine.home().frecent.isEmpty)
    }
}
