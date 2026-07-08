import Foundation
import Testing
@testable import QuickieCore

// A Fallback Action is one that rides the Result list's bottom region and consumes
// the user's literal typed text as its payload (CONTEXT.md → Fallback Action). There
// is no fallback flag: eligibility is derived from shape (a free-text first Argument)
// and *activation* is membership in the SearchEngine's single enabled list. These
// tests pin the derived eligibility and the region behaviour it drives: an enabled
// fallback is present for any non-empty query, pinned bottom, fed the raw query text;
// an eligible-but-pooled one is a normal verb-first match instead.
struct FallbackTests {

    @Test("a static Quicklink is not fallback-eligible")
    func notEligibleByDefault() {
        let link = Action.quicklink(id: "a", title: "Apple", url: URL(string: "https://apple.com")!)
        #expect(link.isFallbackEligible == false)
    }

    @Test("a text-first Custom Action is fallback-eligible by shape — no flag")
    func textFirstCustomActionIsEligible() {
        let search = CustomActionDefinition(
            name: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        ).makeAction(id: "ddg")
        #expect(search?.isFallbackEligible == true)
    }

    @Test("a date/number-first Custom Action is not fallback-eligible")
    func nonTextFirstCustomActionNotEligible() {
        // A first slot that isn't free text has nowhere to put the seeded query.
        let dated = CustomActionDefinition(
            name: "Log at",
            template: "app://log?when={when}&note={note}",
            argumentSpecs: ["when": ArgumentSpec(type: .date)]
        ).makeAction(id: "log")
        #expect(dated?.isFallbackEligible == false)
    }

    // A SearchEngine wired like the app: a couple of name-matchable static links
    // plus a web-search Custom Action the user has enabled as a fallback.
    private func engine() -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    .quicklink(id: "apple", title: "Open Apple", url: URL(string: "https://apple.com")!),
                    .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                    CustomActionDefinition(
                        name: "Search the web",
                        template: "https://duckduckgo.com/?q={query}"
                    ).makeAction(id: "web-search")!,
                ])
            ],
            enabledFallbacks: ["web-search"]
        )
    }

    @Test("an enabled Fallback appears even when nothing matches by name")
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

    @Test("an enabled Fallback is pinned below the name-matches")
    func fallbackPinnedBelowMatches() {
        // "git" name-matches GitHub; the web-search Fallback still rides along,
        // but last — the bottom of the reversed list, farthest from the thumb.
        let ids = engine().results(for: "git").map(\.id)
        #expect(ids == ["github", "web-search"])
    }

    @Test("an enabled Fallback appears once, never duplicated as a name-match")
    func fallbackNotDoubledByNameMatch() {
        // The web-search Fallback's title contains "search"; it must not show up
        // both as a name hit and as a fallback row.
        let ids = engine().results(for: "search").map(\.id)
        #expect(ids == ["web-search"])
        #expect(ids.filter { $0 == "web-search" }.count == 1)
    }

    @Test("an eligible-but-pooled action is a normal verb-first match, not a fallback row")
    func pooledEligibleActionNameMatchesInstead() {
        // Same catalog, but the web-search Custom Action is *not* in the enabled
        // list — it sits in the derived pool. It no longer rides the bottom region;
        // instead it is name-matchable like any Action (startable verb-first).
        let engine = SearchEngine(providers: [
            IndexedProvider(catalog: [
                .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                CustomActionDefinition(name: "Search the web", template: "https://duckduckgo.com/?q={query}").makeAction(id: "web-search")!,
            ])
        ])  // no enabledFallbacks
        // A non-matching query surfaces nothing — the pooled action doesn't ride
        // the region.
        #expect(engine.results(for: "qwerty").isEmpty)
        // But typing its name still finds it as an ordinary ranked match.
        #expect(engine.results(for: "search the web").map(\.id).contains("web-search"))
    }

    @Test("an empty query surfaces no Fallback (Home state)")
    func emptyQueryHasNoFallback() {
        #expect(engine().results(for: "").isEmpty)
        #expect(engine().results(for: "   ").isEmpty)
    }

    @Test("the default web-search Fallback uses the default engine")
    func webSearchDefaultEngine() {
        let search = Action.webSearchFallback()
        #expect(search.isFallbackEligible)
        var session = MultiStepAction(action: search)
        #expect(session.commit(.text("swift"))
                == .completed(.openURL(URL(string: "https://duckduckgo.com/?q=swift")!)))
    }

    @Test("the default search engine is editable — it's just the template")
    func webSearchEngineIsEditable() {
        let google = Action.webSearchFallback(template: "https://www.google.com/search?q={query}")
        #expect(google.isFallbackEligible)
        var session = MultiStepAction(action: google)
        #expect(session.commit(.text("swift"))
                == .completed(.openURL(URL(string: "https://www.google.com/search?q=swift")!)))
    }
}
