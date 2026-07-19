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

    @Test("an enabled Fallback whose name matches appears twice — a ranked match and a fallback row")
    func enabledFallbackDoublesAsNameMatch() {
        // The web-search Fallback's title is "Search the web"; typing "search"
        // name-matches it, so it surfaces **both** as a ranked name-match (startable
        // verb-first, breadcrumb empty) and in the bottom fallback region (CONTEXT.md
        // → Fallback Action; issue #197). The two rows are the same Action but do
        // different things, distinguished by their region.
        let rows = engine().rows(for: "search")
        let web = rows.filter { $0.action.id == "web-search" }
        #expect(web.count == 2)
        #expect(web.contains { $0.region == .ranked })
        #expect(web.contains { $0.region == .fallback })
    }

    @Test("the ranked duplicate bolds its match; the fallback-region row never bolds")
    func rankedDuplicateBoldsFallbackRowDoesNot() {
        let rows = engine().rows(for: "search")
        let ranked = rows.first { $0.action.id == "web-search" && $0.region == .ranked }!
        let fallback = rows.first { $0.action.id == "web-search" && $0.region == .fallback }!
        // The ranked row explains itself: "search" found its place in the title, so
        // some title offsets bold.
        #expect(ranked.match != nil)
        let bold = ranked.match?.titleBold ?? []
        #expect(bold.isEmpty == false)
        // The fallback-region row consumes the query rather than being found by name,
        // so it carries no Match highlight — it never bolds.
        #expect(fallback.match == nil)
    }

    @Test("the ranked name-match sits above the bottom fallback region")
    func rankedDuplicateOrdersAboveFallbackRow() {
        // Both rows are the same Action; the ranked one rides the name-match region
        // (nearer the thumb) and the fallback one is pinned to the very bottom.
        let rows = engine().rows(for: "search")
        let rankedIndex = rows.firstIndex { $0.action.id == "web-search" && $0.region == .ranked }!
        let fallbackIndex = rows.firstIndex { $0.action.id == "web-search" && $0.region == .fallback }!
        #expect(rankedIndex < fallbackIndex)
        // The fallback region is always last.
        #expect(fallbackIndex == rows.count - 1)
    }

    @Test("Enter runs the Highlighted row — the ranked match wins a strong name hit")
    func highlightedRowIsRankedOnStrongNameMatch() {
        // "search" is a strong prefix match on "Search the web", so the ranked
        // duplicate — not the fallback row — is `rows[0]`, the row Enter runs, and it
        // opens the breadcrumb empty (its `.ranked` region drives seed-and-commit).
        let top = engine().highlightedRow(for: "search")
        #expect(top?.action.id == "web-search")
        #expect(top?.region == .ranked)
    }

    @Test("a ranked duplicate ranks by match quality — no fallback boost")
    func rankedDuplicateHasNoSpecialBoost() {
        // A stronger name-match on a *different* action outranks the fallback's ranked
        // duplicate: the duplicate carries no special lift for being a fallback, it
        // competes on match quality like any row. Here "web" exact-prefixes "Web tool"
        // and only substring-matches "Search the web", so the plain action wins the top.
        let engine = SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    .quicklink(id: "webtool", title: "Web tool", url: URL(string: "https://web.example")!),
                    CustomActionDefinition(
                        name: "Search the web",
                        template: "https://duckduckgo.com/?q={query}"
                    ).makeAction(id: "web-search")!,
                ])
            ],
            enabledFallbacks: ["web-search"]
        )
        let rows = engine.rows(for: "web")
        // Top row is the plain prefix match, not the fallback's ranked duplicate.
        #expect(rows.first?.action.id == "webtool")
        // The fallback still surfaces both ways.
        let web = rows.filter { $0.action.id == "web-search" }
        #expect(web.contains { $0.region == .ranked })
        #expect(web.contains { $0.region == .fallback })
    }

    @Test("the Fallbacks master switch off drops both rows — region and ranked")
    func masterSwitchOffDropsBothRows() {
        // Disabling the Fallbacks kind is the master switch over the whole region
        // (issue #67). It drops the enabled fallback entirely — not just its region
        // row but the ranked duplicate too, like any disabled kind.
        let engine = SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    CustomActionDefinition(
                        name: "Search the web",
                        template: "https://duckduckgo.com/?q={query}"
                    ).makeAction(id: "web-search")!,
                ])
            ],
            enabledFallbacks: ["web-search"],
            enablement: ProviderEnablement(disabled: [.fallbacks])
        )
        #expect(engine.rows(for: "search").isEmpty)
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
