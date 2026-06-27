import Foundation
import Testing
@testable import QuickieCore

// A Fallback Action is one flagged to always appear in the Result list and
// consume the user's literal typed text as its payload (CONTEXT.md → Fallback
// Action). The built-in web-search is the canonical one, and *any*
// placeholder-Quicklink can be flagged. These tests pin the flag itself and the
// SearchEngine behavior it drives: fallbacks are pinned in the bottom region,
// present for any non-empty query, fed the raw query text.
struct FallbackTests {

    @Test("an Action is not a Fallback unless flagged")
    func notFallbackByDefault() {
        let link = Action.quicklink(id: "a", title: "Apple", template: "https://apple.com")
        #expect(link.isFallback == false)
    }

    @Test("any placeholder-Quicklink can be flagged a Fallback")
    func placeholderCanBeFlagged() {
        let search = Action.quicklink(
            id: "ddg",
            title: "Search the web",
            template: "https://duckduckgo.com/?q={query}",
            isFallback: true
        )
        #expect(search.isFallback)
    }

    // A SearchEngine wired like the app: a couple of name-matchable links plus a
    // web-search Fallback that consumes whatever the user typed.
    private func engine() -> SearchEngine {
        SearchEngine(providers: [
            IndexedProvider(catalog: [
                .quicklink(id: "apple", title: "Open Apple", template: "https://apple.com"),
                .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], template: "https://github.com"),
                .quicklink(
                    id: "web-search", title: "Search the web",
                    template: "https://duckduckgo.com/?q={query}", isFallback: true
                ),
            ])
        ])
    }

    @Test("a Fallback appears even when nothing matches by name")
    func fallbackAppearsForNonMatchingQuery() {
        // "qwerty" matches none of the link names; only the Fallback can serve it.
        let ids = engine().results(for: "qwerty").map(\.id)
        #expect(ids == ["web-search"])
    }

    @Test("a Fallback consumes the raw typed text as its Argument")
    func fallbackConsumesRawText() {
        let fallback = engine().results(for: "swift testing").first { $0.id == "web-search" }!
        #expect(fallback.run(input: "swift testing")
                == .openURL(URL(string: "https://duckduckgo.com/?q=swift%20testing")!))
    }

    @Test("a Fallback is pinned below the name-matches")
    func fallbackPinnedBelowMatches() {
        // "git" name-matches GitHub; the web-search Fallback still rides along,
        // but last — the bottom of the reversed list, farthest from the thumb.
        let ids = engine().results(for: "git").map(\.id)
        #expect(ids == ["github", "web-search"])
    }

    @Test("a Fallback appears once, never duplicated as a name-match")
    func fallbackNotDoubledByNameMatch() {
        // The web-search Fallback's title contains "search"; it must not show up
        // both as a name hit and as a fallback row.
        let ids = engine().results(for: "search").map(\.id)
        #expect(ids == ["web-search"])
        #expect(ids.filter { $0 == "web-search" }.count == 1)
    }

    @Test("an empty query surfaces no Fallback (Home state)")
    func emptyQueryHasNoFallback() {
        #expect(engine().results(for: "").isEmpty)
        #expect(engine().results(for: "   ").isEmpty)
    }

    @Test("the built-in web-search Fallback uses the default engine")
    func webSearchDefaultEngine() {
        let search = Action.webSearch()
        #expect(search.isFallback)
        #expect(search.run(input: "swift")
                == .openURL(URL(string: "https://duckduckgo.com/?q=swift")!))
    }

    @Test("the default search engine is editable — it's just the template")
    func webSearchEngineIsEditable() {
        let google = Action.webSearch(template: "https://www.google.com/search?q={query}")
        #expect(google.isFallback)
        #expect(google.run(input: "swift")
                == .openURL(URL(string: "https://www.google.com/search?q=swift")!))
    }
}
