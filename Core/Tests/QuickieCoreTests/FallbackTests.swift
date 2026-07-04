import Foundation
import Testing
@testable import QuickieCore

// A Fallback Action is one flagged to always appear in the Result list and
// consume the user's literal typed text as its payload (CONTEXT.md → Fallback
// Action). The default web-search Custom Action is the canonical fallback. These
// tests pin the flag itself and the SearchEngine behaviour it drives: fallbacks
// are pinned in the bottom region, present for any non-empty query, fed the raw
// query text.
struct FallbackTests {

    @Test("a static Quicklink is not a Fallback")
    func notFallbackByDefault() {
        let link = Action.quicklink(id: "a", title: "Apple", url: URL(string: "https://apple.com")!)
        #expect(link.isFallback == false)
    }

    @Test("a fallback-flagged Custom Action is flagged a Fallback")
    func customActionIsFlagged() {
        let search = CustomActionDefinition(
            name: "Search the web",
            template: "https://duckduckgo.com/?q={query}",
            isFallback: true
        ).makeAction(id: "ddg")
        #expect(search?.isFallback == true)
    }

    // A SearchEngine wired like the app: a couple of name-matchable static links
    // plus a web-search Custom Action (fallback-flagged) that consumes whatever the
    // user typed.
    private func engine() -> SearchEngine {
        SearchEngine(providers: [
            IndexedProvider(catalog: [
                .quicklink(id: "apple", title: "Open Apple", url: URL(string: "https://apple.com")!),
                .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                CustomActionDefinition(
                    name: "Search the web",
                    template: "https://duckduckgo.com/?q={query}",
                    isFallback: true
                ).makeAction(id: "web-search")!,
            ])
        ])
    }

    @Test("a Fallback appears even when nothing matches by name")
    func fallbackAppearsForNonMatchingQuery() {
        // "qwerty" matches none of the link names; only the Fallback can serve it.
        let ids = engine().results(for: "qwerty").map(\.id)
        #expect(ids == ["web-search"])
    }

    @Test("a Fallback consumes the raw typed text as its Argument (seed-and-commit)")
    func fallbackConsumesRawText() {
        // Selecting a fallback seeds-and-commits the typed query as Argument 1
        // through the normal engine (CONTEXT.md → Fallback Action): a one-Argument
        // fallback completes in one tap with the filled URL.
        let fallback = engine().results(for: "swift testing").first { $0.id == "web-search" }!
        var session = MultiStepAction(action: fallback)
        #expect(session.commit(.text("swift testing"))
                == .completed(.openURL(URL(string: "https://duckduckgo.com/?q=swift%20testing")!)))
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

    @Test("the default web-search Fallback uses the default engine")
    func webSearchDefaultEngine() {
        let search = Action.webSearchFallback()
        #expect(search.isFallback)
        var session = MultiStepAction(action: search)
        #expect(session.commit(.text("swift"))
                == .completed(.openURL(URL(string: "https://duckduckgo.com/?q=swift")!)))
    }

    @Test("the default search engine is editable — it's just the template")
    func webSearchEngineIsEditable() {
        let google = Action.webSearchFallback(template: "https://www.google.com/search?q={query}")
        #expect(google.isFallback)
        var session = MultiStepAction(action: google)
        #expect(session.commit(.text("swift"))
                == .completed(.openURL(URL(string: "https://www.google.com/search?q=swift")!)))
    }
}
