import Foundation
import Testing
@testable import QuickieCore

// The SearchEngine is the whole loop minus the pixels: providers in, a ranked
// Result list out. These tests read like the spec for the skeleton — what the
// user sees when they type, and what tapping the top row does.
struct SearchEngineTests {

    private func engine() -> SearchEngine {
        SearchEngine(providers: [
            IndexedProvider(catalog: [
                .staticLink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                .staticLink(id: "apple", title: "Open Apple", url: URL(string: "https://apple.com")!),
                .staticLink(id: "wikipedia", title: "Open Wikipedia", aliases: ["wiki"], url: URL(string: "https://wikipedia.org")!),
            ])
        ])
    }

    @Test("an empty query yields no results (Home state)")
    func emptyQueryIsHome() {
        #expect(engine().results(for: "").isEmpty)
    }

    @Test("a whitespace-only query yields no results")
    func whitespaceQueryIsHome() {
        #expect(engine().results(for: "   ").isEmpty)
    }

    @Test("typing filters out actions that do not match")
    func filtersNonMatches() {
        let ids = engine().results(for: "github").map(\.id)
        #expect(ids == ["github"])
    }

    @Test("the best match ranks first")
    func bestMatchRanksFirst() {
        // "apple" is an exact-ish match for "Open Apple" and matches nothing
        // else; "open" matches all three, with the shortest title tightest.
        let ids = engine().results(for: "apple").map(\.id)
        #expect(ids.first == "apple")
    }

    @Test("a shared prefix returns every match, best fit first")
    func sharedPrefixRanksByFit() {
        let ids = engine().results(for: "open").map(\.id)
        // All three contain "Open …"; the tighter (shorter) title fits best.
        #expect(Set(ids) == ["github", "apple", "wikipedia"])
        #expect(ids.first == "apple") // "Open Apple" is the shortest candidate
    }

    @Test("an alias matches even when the title does not")
    func aliasMatches() {
        let ids = engine().results(for: "wiki").map(\.id)
        #expect(ids.contains("wikipedia"))
    }

    @Test("results merge across multiple providers")
    func mergesProviders() {
        let engine = SearchEngine(providers: [
            IndexedProvider(catalog: [.staticLink(id: "a", title: "Alpha", url: URL(string: "https://a.example")!)]),
            IndexedProvider(catalog: [.staticLink(id: "b", title: "Alphabet", url: URL(string: "https://b.example")!)]),
        ])
        #expect(Set(engine.results(for: "alpha").map(\.id)) == ["a", "b"])
    }

    @Test("a fat-fingered query still surfaces its action")
    func surfacesTypoMatch() {
        // "gtihub" swaps two letters of "GitHub" — the forgiving matcher should
        // still float it into the Result list.
        let ids = engine().results(for: "gtihub").map(\.id)
        #expect(ids.contains("github"))
    }

    @Test("the engine matches through its configured keyboard layout")
    func honorsConfiguredLayout() {
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [
                .staticLink(id: "zoom", title: "Zoom", url: URL(string: "https://zoom.us")!),
            ])],
            layout: .azerty
        )
        // 'e' sits beside 'z' on AZERTY: "eoom" is a plausible slip for "Zoom".
        #expect(engine.results(for: "eoom").map(\.id).contains("zoom"))
    }

    @Test("running the top result's main action performs its effect end-to-end")
    func runTopResultMainAction() {
        // type → ranked result → run: the tracer bullet through the core.
        let top = engine().results(for: "github").first!
        #expect(top.run() == .openURL(URL(string: "https://github.com")!))
    }
}
