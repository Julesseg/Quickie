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
                .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                .quicklink(id: "apple", title: "Open Apple", url: URL(string: "https://apple.com")!),
                .quicklink(id: "wikipedia", title: "Open Wikipedia", aliases: ["wiki"], url: URL(string: "https://wikipedia.org")!),
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
            IndexedProvider(catalog: [.quicklink(id: "a", title: "Alpha", url: URL(string: "https://a.example")!)]),
            IndexedProvider(catalog: [.quicklink(id: "b", title: "Alphabet", url: URL(string: "https://b.example")!)]),
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
                .quicklink(id: "zoom", title: "Zoom", url: URL(string: "https://zoom.us")!),
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

    // A Dynamic Provider that always injects one result, regardless of the
    // query — a stand-in for the Calculator, exercising the boost path without
    // depending on the evaluator.
    private struct AlwaysProvider: Provider {
        let kind: ProviderKind = .dynamic
        func candidates(for query: String) -> [Action] {
            [Action(id: "dynamic", title: "= 161", outputType: .number) { _ in .copyText("161") }]
        }
    }

    @Test("a Dynamic Provider's result floats to the top, above name-matches")
    func dynamicResultIsBoostedToTop() {
        // ADR 0008: a type-triggered result is injected with boosted rank so it
        // reads as a top hit even though its title ("= 161") is not a name match
        // for the query.
        let engine = SearchEngine(providers: [
            IndexedProvider(catalog: [
                .quicklink(id: "github", title: "Open GitHub", url: URL(string: "https://github.com")!),
            ]),
            AlwaysProvider(),
        ])
        let ids = engine.results(for: "github").map(\.id)
        #expect(ids.first == "dynamic")
        #expect(ids.contains("github"))
    }

    @Test("a Dynamic Provider's result survives even when it matches nothing by name")
    func dynamicResultNotDroppedByMatcher() {
        // The calculator answer "= 161" shares no letters with "23*7"; the
        // matcher would drop it. The engine must show it anyway — the Provider
        // already decided it applies.
        let engine = SearchEngine(providers: [
            IndexedProvider(catalog: [
                .quicklink(id: "github", title: "Open GitHub", url: URL(string: "https://github.com")!),
            ]),
            AlwaysProvider(),
        ])
        #expect(engine.results(for: "23*7").map(\.id) == ["dynamic"])
    }

    // MARK: - Ranked-dynamic (File Search, ADR 0015)

    private func engineWithFiles(_ entries: [FileEntry], command: Action) -> SearchEngine {
        SearchEngine(providers: [
            IndexedProvider(catalog: [command]),
            FileSearchProvider(index: FilenameIndex(entries: entries)),
        ])
    }

    @Test("a ranked-dynamic file flows into the ranked region, scored — not boosted to the top")
    func rankedDynamicFileIsScoredNotBoosted() {
        // Unlike the Calculator, a File Search hit does not float above name
        // matches (ADR 0015). An exact command name outranks a strong filename hit.
        let engine = engineWithFiles(
            [FileEntry(bookmarkID: "f", relativePath: "reports.pdf")],
            command: .quicklink(id: "reports-cmd", title: "reports", url: URL(string: "https://x.example")!)
        )
        let ids = engine.results(for: "reports").map(\.id)
        // Both surface, but the exact command name is first — the file is ranked
        // below it, not boosted above it.
        #expect(ids.first == "reports-cmd")
        #expect(ids.contains("file.f.reports.pdf"))
    }

    @Test("a strong file match still outranks a weaker name match by score")
    func fileOutranksWeakerNameMatchByScore() {
        // The file is a prefix match (strong); the command is only a buried
        // substring (weak) — so the file ranks above it. Placement is by score,
        // not by provider: ranked-dynamic candidates compete on match quality.
        let engine = engineWithFiles(
            [FileEntry(bookmarkID: "f", relativePath: "reporter.txt")],
            command: .quicklink(id: "weak", title: "xreportx", url: URL(string: "https://x.example")!)
        )
        let ids = engine.results(for: "report").map(\.id)
        #expect(ids.first == "file.f.reporter.txt")
    }

    @Test("files never enter Home — not as Favorites, not in the Frecency list")
    func filesNeverEnterHome() {
        let now = Date()
        var frecency = Frecency()
        frecency.record("file.f.report.pdf", at: now) // even if a file were "used"
        let engine = SearchEngine(
            providers: [
                IndexedProvider(catalog: [.quicklink(id: "a", title: "Alpha", url: URL(string: "https://a.example")!)]),
                FileSearchProvider(index: FilenameIndex(entries: [
                    FileEntry(bookmarkID: "f", relativePath: "report.pdf"),
                ])),
            ],
            favorites: ["file.f.report.pdf"], // even if a file were pinned
            frecency: frecency,
            now: now
        )
        // A ranked-dynamic provider is not indexed, so its files resolve nowhere on
        // Home: no Favorite, no Frecency row, and the id reconciles away.
        #expect(engine.home().favorites.isEmpty)
        #expect(engine.home().frecent.isEmpty)
        #expect(engine.resolvableHomeIDs().contains("file.f.report.pdf") == false)
    }

    @Test("a substring file match surfaces inline but below a strong name match")
    func substringFileMatchRanksBelowStrongNameMatch() {
        // The provider gates on the substring threshold (ADR 0035), so a buried
        // substring ("port" in "report.pdf") surfaces inline — but it sits below
        // the engine's strong tier, so the prefix-matched command still wins.
        let engine = engineWithFiles(
            [FileEntry(bookmarkID: "f", relativePath: "report.pdf")],
            command: .quicklink(id: "portal", title: "Portal", url: URL(string: "https://x.example")!)
        )
        let ids = engine.results(for: "port").map(\.id)
        #expect(ids.first == "portal")
        #expect(ids.contains("file.f.report.pdf"))
    }

    @Test("scattered and typo file matches are held back from the inline Result list")
    func weakFileMatchesHeldBackInline() {
        // Below the substring threshold nothing surfaces inline: a scattered
        // subsequence ("rport") and a typo ("reprot") of "report.pdf" appear
        // only in the Search Files context (ADR 0014).
        let engine = engineWithFiles(
            [FileEntry(bookmarkID: "f", relativePath: "report.pdf")],
            command: .quicklink(id: "portal", title: "Portal", url: URL(string: "https://x.example")!)
        )
        #expect(engine.results(for: "rport").map(\.id).contains("file.f.report.pdf") == false)
        #expect(engine.results(for: "reprot").map(\.id).contains("file.f.report.pdf") == false)
    }
}
