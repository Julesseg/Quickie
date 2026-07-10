import Foundation
import Testing
@testable import QuickieCore

// The empty-query Home state (CONTEXT.md → Home; issue #9 AC #1, #2): a row of
// pinned Favorites and an auto Frecency list of recently/often-used Actions.
// `home()` is the empty-query sibling of `results(for:)` — it composes those two
// sections from the same providers + signals the engine already holds.
struct HomeTests {

    private func link(_ id: String, _ title: String) -> Action {
        .quicklink(id: id, title: title, url: URL(string: "https://\(id).example")!)
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

    @Test("a pinned Fallback draws a Favorite card on Home")
    func pinnedFallbackSurfacesInFavorites() {
        // A *standalone-runnable* fallback-eligible Indexed Action — a text-first
        // Custom Action — is part of the enumerable catalog: pinning it must draw a
        // card that launches it verb-first, like any other pin. (Save for later is
        // *not* pinnable — its silent Pile write does nothing run without a query;
        // issue #140.)
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [.webSearchFallback()])],
            favorites: ["builtin.web-search"],
            enabledFallbacks: [Action.webSearchFallbackID]
        )
        #expect(engine.home().favorites.map(\.id) == ["builtin.web-search"])
    }

    @Test("an enabled Fallback stays out of the Recent list")
    func enabledFallbacksExcludedFromRecents() {
        // An action currently riding the fallback region records frecency like any
        // selection (web search fires on every fallback search), but it already sits
        // at the bottom of every Result list — auto-surfacing it again on Home would
        // only be noise. Only a manual pin puts an enabled fallback on Home.
        let now = Date()
        var frecency = Frecency()
        frecency.record("builtin.web-search", at: now)
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [.webSearchFallback()])],
            frecency: frecency,
            now: now,
            enabledFallbacks: [Action.webSearchFallbackID]
        )
        #expect(engine.home().frecent.isEmpty)
    }

    @Test("a disabled pinned Fallback drops from the grid but keeps its pin")
    func disabledPinnedFallbackLeavesTheGridButKeepsResolving() {
        // Both disable axes hide the card (CONTEXT.md → Disabled, Fallback list) —
        // the Fallbacks master switch and the action's instance-disable — while the
        // id keeps resolving, so the pin survives reconciliation and the card returns
        // on re-enable. (Demotion to the pool is *not* one of these: a pooled eligible
        // action still draws its card.)
        let providers: [Provider] = [IndexedProvider(catalog: [.webSearchFallback()])]
        let enabled = [Action.webSearchFallbackID]

        let masterOff = SearchEngine(
            providers: providers,
            favorites: ["builtin.web-search"],
            enabledFallbacks: enabled,
            enablement: ProviderEnablement(disabled: [.fallbacks])
        )
        #expect(masterOff.home().favorites.isEmpty)
        #expect(masterOff.resolvableHomeIDs().contains("builtin.web-search"))

        let instanceOff = SearchEngine(
            providers: providers,
            favorites: ["builtin.web-search"],
            enabledFallbacks: enabled,
            disabledInstances: ["builtin.web-search"]
        )
        #expect(instanceOff.home().favorites.isEmpty)
        #expect(instanceOff.resolvableHomeIDs().contains("builtin.web-search"))
    }

    @Test("Show Recents off hides the Recent list but keeps the Favorites grid")
    func showRecentsOffHidesOnlyTheRecentList() {
        // The app-level **Show Recents** toggle (CONTEXT.md → Settings; issue
        // #65): off suppresses the Frecency "Recent" section on Home, leaving the
        // pinned Favorites untouched. The signals themselves keep recording —
        // this hides the surface, it doesn't forget the history.
        let now = Date()
        var frecency = Frecency()
        frecency.record("a", at: now)
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a", "Alpha"), link("b", "Bravo")])],
            favorites: ["b"],
            frecency: frecency,
            now: now
        )
        let home = engine.home(showRecents: false)
        #expect(home.frecent.isEmpty)
        #expect(home.favorites.map(\.id) == ["b"])
    }

    @Test("resolvableHomeIDs lists every indexed id")
    func resolvableHomeIDsCoversIndexedCatalog() {
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a", "Alpha"), link("b", "Bravo")])]
        )
        #expect(engine.resolvableHomeIDs() == ["a", "b"])
    }

    @Test("resolvableHomeIDs includes Fallbacks, so a Fallback pin survives reconciliation")
    func resolvableHomeIDsIncludesFallbacks() {
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [link("a", "Alpha"), .webSearchFallback()])]
        )
        // A pinned Fallback resolves to a Home card, so its id must be here —
        // otherwise the App's reconciliation would prune the pin at launch.
        #expect(engine.resolvableHomeIDs() == ["a", "builtin.web-search"])
    }
}
