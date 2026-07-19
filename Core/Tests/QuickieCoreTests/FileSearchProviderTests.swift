import Foundation
import Testing
@testable import QuickieCore

// File Search is the **ranked-dynamic** Provider (CONTEXT.md → File Search; ADR
// 0015): it owns its own filename snapshot and prefilters it — so a large file
// set never floods the central catalog — then scores the survivors with the
// Matcher, keeps only contiguous (substring-or-better) matches (ADR 0035), and
// caps how many surface inline. These tests pin that behaviour against a plain
// in-memory index; the SearchEngine tests cover where the survivors then land
// in the Result list.
struct FileSearchProviderTests {

    private func provider(_ entries: [FileEntry], inlineCap: Int = 3) -> FileSearchProvider {
        FileSearchProvider(index: FilenameIndex(entries: entries), inlineCap: inlineCap)
    }

    @Test("it is a ranked-dynamic provider")
    func kindIsRankedDynamic() {
        #expect(provider([]).kind == .rankedDynamic)
    }

    @Test("an empty or whitespace query yields nothing")
    func emptyQueryDeclines() {
        let p = provider([FileEntry(bookmarkID: "f", relativePath: "report.pdf")])
        #expect(p.candidates(for: "").isEmpty)
        #expect(p.candidates(for: "   ").isEmpty)
    }

    @Test("a strong filename match surfaces as a file Action")
    func strongMatchSurfaces() {
        let p = provider([
            FileEntry(bookmarkID: "f1", relativePath: "docs/report.pdf"),
            FileEntry(bookmarkID: "f1", relativePath: "budget.xlsx"),
        ])
        let hits = p.candidates(for: "report")
        #expect(hits.count == 1)
        #expect(hits.first?.title == "report.pdf")
        // It carries only its bookmark identity + relative path (Core stays pure).
        #expect(hits.first?.run() == .openFile(bookmarkID: "f1", relativePath: "docs/report.pdf"))
    }

    @Test("contiguous matches surface inline; scattered and typo hits are held back")
    func weakMatchesHeldBack() {
        let p = provider([FileEntry(bookmarkID: "f", relativePath: "report.pdf")])
        // A buried substring ("port" inside "report.pdf") is contiguous, so it
        // surfaces inline (ADR 0035), as does a prefix.
        #expect(p.candidates(for: "port").count == 1)
        #expect(p.candidates(for: "rep").count == 1)
        // A scattered subsequence and a typo score below the substring
        // threshold, so they surface only in the uncapped Search Files context
        // (ADR 0014).
        #expect(p.candidates(for: "rport").isEmpty)
        #expect(p.candidates(for: "reprot").isEmpty)
    }

    @Test("the inline cap bounds how many files surface at once")
    func inlineCapBoundsResults() {
        let entries = (1...10).map { FileEntry(bookmarkID: "f", relativePath: "report-\($0).pdf") }
        let hits = provider(entries, inlineCap: 3).candidates(for: "report")
        #expect(hits.count == 3)
    }

    @Test("survivors are ordered best match first")
    func survivorsOrderedByScore() {
        // An exact filename beats a prefix beats a longer prefix — the Matcher's
        // ordering, surfaced in the provider's own ranking of its handful.
        let p = provider([
            FileEntry(bookmarkID: "f", relativePath: "reporting-tool.md"),
            FileEntry(bookmarkID: "f", relativePath: "report.md"),
            FileEntry(bookmarkID: "f", relativePath: "reports.md"),
        ], inlineCap: 3)
        let titles = p.candidates(for: "report.md").map(\.title)
        #expect(titles.first == "report.md") // exact match ranks first
    }

    @Test("ties break deterministically so results never reshuffle between runs")
    func deterministicTieBreak() {
        let entries = [
            FileEntry(bookmarkID: "f", relativePath: "b/report.pdf"),
            FileEntry(bookmarkID: "f", relativePath: "a/report.pdf"),
        ]
        // Equal score (same filename) → stable order by relative path.
        let first = provider(entries).candidates(for: "report").map(\.id)
        let second = provider(entries).candidates(for: "report").map(\.id)
        #expect(first == second)
    }
}
