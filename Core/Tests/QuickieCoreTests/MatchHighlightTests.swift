import Foundation
import Testing
@testable import QuickieCore

// The Match highlight (CONTEXT.md → Match highlight; issue #195): the letters of
// the query that found their place in a result's name render bold, so the row
// explains *why* it surfaced. These tests pin the alignment tiers — contiguous vs
// scattered subsequence, multi-token union, and the typo-tier exact-alignment rule
// — plus the engine's single-source rule (an alias winner leaves the title plain)
// and the region rule (only name-matched rows bold).
struct MatchHighlightTests {

    // MARK: - Matcher alignment tiers

    @Test("a prefix query bolds the leading contiguous run")
    func prefixBoldsLeadingRun() {
        // "git" is a prefix of "GitHub" — bold exactly those three leading letters.
        #expect(Matcher.matchOffsets(query: "git", candidate: "GitHub") == [0, 1, 2])
    }

    @Test("a buried substring bolds the leftmost contiguous occurrence")
    func buriedSubstringBoldsLeftmostRun() {
        // "git" sits mid-string in "Open GitHub" (offsets 5–7 of "open github").
        #expect(Matcher.matchOffsets(query: "git", candidate: "Open GitHub") == [5, 6, 7])
    }

    @Test("a repeated substring bolds only the leftmost run")
    func repeatedSubstringBoldsLeftmost() {
        // "an" occurs twice in "Banana"; the leftmost run (offsets 1–2) wins, not a
        // scattered spread across both.
        #expect(Matcher.matchOffsets(query: "an", candidate: "Banana") == [1, 2])
    }

    @Test("a scattered subsequence bolds its greedy leftmost embedding")
    func scatteredSubsequenceBoldsGreedyEmbedding() {
        // "ghb" is not contiguous in "GitHub"; greedily embed g(0) h(3) b(5).
        #expect(Matcher.matchOffsets(query: "ghb", candidate: "GitHub") == [0, 3, 5])
    }

    @Test("a multi-word query bolds the union of per-token alignments")
    func multiWordBoldsUnion() {
        // "github open" → "Open GitHub": "open" prefixes offsets 0–3, "github" the
        // run 5–10 — the union bolds, order-independent.
        #expect(
            Matcher.matchOffsets(query: "github open", candidate: "Open GitHub")
                == [0, 1, 2, 3, 5, 6, 7, 8, 9, 10]
        )
    }

    @Test("a dropped-character typo bolds only the exactly-aligned letters")
    func deletionTypoBoldsAlignedLetters() {
        // "gthub" is missing the 'i' of "GitHub": bold G, t, H, u, b — the 'i' at
        // offset 1 stays plain. "G·tHub".
        #expect(Matcher.matchOffsets(query: "gthub", candidate: "GitHub") == [0, 2, 3, 4, 5])
    }

    @Test("a substituted position stays plain")
    func substitutionStaysPlain() {
        // "githib" types 'i' where 'u' belongs: bold Gith and b, leaving the 'u' at
        // offset 4 plain. "Gith·b".
        #expect(Matcher.matchOffsets(query: "githib", candidate: "GitHub") == [0, 1, 2, 3, 5])
    }

    @Test("bolding is diacritic- and case-faithful")
    func diacriticFaithful() {
        // "cafe" matches "Café": offset 3 is the accented 'é', which must bold.
        #expect(Matcher.matchOffsets(query: "cafe", candidate: "Café") == [0, 1, 2, 3])
    }

    @Test("a non-match has no alignment")
    func nonMatchHasNoAlignment() {
        #expect(Matcher.matchOffsets(query: "zzz", candidate: "GitHub") == nil)
        #expect(Matcher.matchOffsets(query: "", candidate: "GitHub") == nil)
    }

    @Test("the alignment agrees with the matcher's accept/reject decision")
    func alignmentAgreesWithScore() {
        // Whatever `score` accepts, `matchOffsets` must align — and whatever it
        // rejects, `matchOffsets` must decline. Beyond the edit budget → neither.
        #expect(Matcher.score(query: "gxywub", candidate: "GitHub") == nil)
        #expect(Matcher.matchOffsets(query: "gxywub", candidate: "GitHub") == nil)
    }

    // MARK: - Engine rows: region and the single-source rule

    private func engine(
        catalog: [Action],
        fallbacks: [String] = []
    ) -> SearchEngine {
        SearchEngine(providers: [IndexedProvider(catalog: catalog)], enabledFallbacks: fallbacks)
    }

    @Test("a ranked name-match row carries a title Match highlight")
    func rankedRowCarriesHighlight() {
        let engine = engine(catalog: [
            .quicklink(id: "github", title: "GitHub", url: URL(string: "https://github.com")!)
        ])
        let row = engine.rows(for: "git").first { $0.action.id == "github" }
        #expect(row?.region == .ranked)
        #expect(row?.match?.winningCandidate == .title)
        #expect(row?.match?.titleBold == [0, 1, 2])
    }

    @Test("when an alias out-scores the title, the title stays plain")
    func aliasWinnerLeavesTitlePlain() {
        // Title "Open GitHub" only *contains* "git" (buried, 0.6-tier); the alias
        // "git" is an exact match (1.0), so the alias wins and the title bolds
        // nothing — the single-source rule.
        let engine = engine(catalog: [
            .quicklink(id: "gh", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!)
        ])
        let row = engine.rows(for: "git").first { $0.action.id == "gh" }
        #expect(row?.match?.winningCandidate == .alias(0))
        #expect(row?.match?.titleBold == [])
    }

    @Test("the title wins a tie against an alias")
    func titleWinsTie() {
        // Both the title and the alias are exact matches for "note"; the title must
        // win the tie so it bolds rather than the alias claiming it.
        let engine = engine(catalog: [
            .quicklink(id: "n", title: "note", aliases: ["note"], url: URL(string: "https://n.example")!)
        ])
        let row = engine.rows(for: "note").first { $0.action.id == "n" }
        #expect(row?.match?.winningCandidate == .title)
        #expect(row?.match?.titleBold == [0, 1, 2, 3])
    }

    @Test("a Pile entry whose body-as-alias wins leaves the title plain")
    func pileBodyAliasWinsLeavesTitlePlain() {
        // A Pile entry's display title is its first line; the whole body rides as a
        // hidden alias. A query buried in the body but not the title bolds nothing on
        // the title — the alias-pill ticket will bold the body side.
        let engine = engine(catalog: [
            .pileEntry(id: "p", text: "Groceries\nremember the oatmilk")
        ])
        let row = engine.rows(for: "oatmilk").first { $0.action.id == "p" }
        #expect(row?.match?.winningCandidate != .title)
        #expect(row?.match?.titleBold == [])
    }

    @Test("boosted, fallback, and Home rows never carry a Match highlight")
    func nonRankedRowsNeverBold() {
        let engine = SearchEngine(
            providers: [
                ComputedProvider(),
                IndexedProvider(catalog: [
                    .quicklink(id: "github", title: "GitHub", url: URL(string: "https://github.com")!),
                    .webSearchFallback(),
                ]),
            ],
            enabledFallbacks: [Action.webSearchFallbackID]
        )
        // A boosted Computed row (a math answer) never name-matched.
        let boosted = engine.rows(for: "2+2").first { $0.region == .boosted }
        #expect(boosted != nil)
        #expect(boosted?.match == nil)
        // The fallback row rides the bottom region and consumes the query — no bold.
        let fallback = engine.rows(for: "2+2").first { $0.region == .fallback }
        #expect(fallback?.match == nil)
        // Home rows aren't produced by `rows(for:)` at all (empty query → []).
        #expect(engine.rows(for: "").isEmpty)
    }

    @Test("results and highlighted stay in step with rows")
    func flatProjectionsMatchRows() {
        let engine = engine(catalog: [
            .quicklink(id: "github", title: "GitHub", url: URL(string: "https://github.com")!)
        ])
        #expect(engine.results(for: "git").map(\.id) == engine.rows(for: "git").map(\.action.id))
        #expect(engine.highlighted(for: "git")?.id == engine.highlightedRow(for: "git")?.action.id)
    }

    // MARK: - File rows bold identically on both surfaces

    @Test("a file row bolds identically inline and in the Search Files context")
    func fileRowBoldsIdentically() {
        let index = FilenameIndex(entries: [
            FileEntry(bookmarkID: "b", relativePath: "Report.pdf")
        ])
        // Inline: through the engine as a ranked-dynamic survivor.
        let engine = SearchEngine(providers: [FileSearchProvider(index: index)])
        let inline = engine.rows(for: "report").first { $0.action.kind == .file }
        // Context: through the provider's uncapped, ungated path.
        let context = FileSearchProvider(index: index).contextRows(for: "report").first
        #expect(inline?.match?.titleBold == [0, 1, 2, 3, 4, 5])
        #expect(inline?.match?.titleBold == context?.match?.titleBold)
        #expect(context?.region == .ranked)
    }

    @Test("the browse-all context list carries no highlight")
    func browseAllHasNoHighlight() {
        let index = FilenameIndex(entries: [
            FileEntry(bookmarkID: "b", relativePath: "Report.pdf")
        ])
        let rows = FileSearchProvider(index: index).contextRows(for: "")
        #expect(rows.first?.match == nil)
    }
}
