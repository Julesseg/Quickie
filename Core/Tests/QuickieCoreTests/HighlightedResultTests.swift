import Foundation
import Testing
@testable import QuickieCore

// The highlighted result is the single best row — `results[0]`, nearest the
// thumb — and pressing Enter runs exactly its main action (CONTEXT.md →
// Highlighted result). On Home (empty query) there is no highlighted result and
// Enter does nothing. Its Enter intent is signalled by mapping the Return key to
// the closest system submit label (.search for a web query, .go for a link).
struct HighlightedResultTests {

    private func engine() -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                    .webSearchFallback(),
                ])
            ],
            enabledFallbacks: [Action.webSearchFallbackID]
        )
    }

    @Test("the highlighted result is the best row, results[0]")
    func highlightedIsFirst() {
        let engine = engine()
        let highlighted = engine.highlighted(for: "git")
        #expect(highlighted?.id == engine.results(for: "git").first?.id)
        #expect(highlighted?.id == "github")
    }

    @Test("an empty query has no highlighted result — Enter is a no-op")
    func emptyQueryHasNoHighlight() {
        #expect(engine().highlighted(for: "") == nil)
        #expect(engine().highlighted(for: "   ") == nil)
    }

    @Test("the Return key reads as .search for a web-query highlight")
    func searchLabelForFallbackQuery() {
        // "qwerty" matches nothing by name; the web-search Custom Action is the
        // highlight, and Enter would search.
        let highlighted = engine().highlighted(for: "qwerty")
        #expect(highlighted?.returnKeyLabel == .search)
    }

    @Test("the Return key reads as .go for a link highlight")
    func goLabelForLink() {
        let highlighted = engine().highlighted(for: "git")
        #expect(highlighted?.returnKeyLabel == .go)
    }

    @Test("a copy/silent-capture highlight reads as .done")
    func doneLabelForSelfContained() {
        #expect(Action.snippet(id: "s", title: "Reply", body: "hi").returnKeyLabel == .done)
        #expect(Action.saveForLater().returnKeyLabel == .done)
        // A math result copies *and* stages, but its Enter intent still reads as
        // Copy-done — the staging is the "also", not a distinct submit label.
        #expect(ComputedProvider().candidates(for: "2+2").first?.returnKeyLabel == .done)
    }

    @Test("a multi-step capture row reads as .go — Enter begins the capture")
    func goLabelForMultiStepCapture() {
        // New Reminder collects Arguments through the breadcrumb; its plain `run()`
        // outcome is `.none`, so the label must come from its having Arguments, not
        // the outcome — Enter on the highlighted row starts the capture.
        #expect(Action.newReminder().returnKeyLabel == .go)
    }

    // MARK: - The highlight the arrow keys moved (issue #267)

    @Test("the highlight starts on the best row, as it always did")
    func selectionStartsOnTheBestRow() {
        // The engine ranks; it does not select. Its `highlightedRow` is where the
        // highlight *starts* — rank 0 — and a primed selection over the same rows
        // agrees with it, which is what makes typing's re-prime a no-op for anyone
        // who never touches an arrow key.
        let engine = engine()
        let rows = engine.rows(for: "git")
        #expect(engine.highlightedRow(for: "git")?.action.id == rows.first?.action.id)
        #expect(ResultSelection.primed.highlightedRow(in: rows)?.action.id == rows.first?.action.id)
    }

    @Test("a moved selection highlights that row, and the ranking is untouched")
    func movedSelectionHighlightsItsRow() {
        let engine = engine()
        let rows = engine.rows(for: "git")
        #expect(rows.count > 1, "the fixture needs a second row to walk onto")
        let moved = ResultSelection.primed.moved(.up, resultCount: rows.count)
        #expect(moved.highlightedRow(in: rows)?.action.id == rows[1].action.id)
        // Selection moves; ranking does not.
        #expect(engine.rows(for: "git").map(\.action.id) == rows.map(\.action.id))
    }

    @Test("the Return-key label follows the highlight onto the moved row")
    func returnKeyLabelFollowsTheMovedHighlight() {
        // "git" ranks the GitHub link first and the web-search fallback beneath it,
        // so walking the highlight up one row swaps Enter's meaning from Go to
        // Search — the label is a property of the *highlighted* row, not of rank 0.
        let rows = engine().rows(for: "git")
        let moved = ResultSelection.primed.moved(.up, resultCount: rows.count)
        #expect(ResultSelection.primed.highlightedRow(in: rows)?.action.returnKeyLabel == .go)
        #expect(moved.highlightedRow(in: rows)?.action.returnKeyLabel == .search)
    }

    @Test("an empty query has no highlighted row however far the selection walked")
    func emptyQueryIgnoresTheSelection() {
        let moved = ResultSelection.primed.moved(.up, resultCount: 5)
        #expect(moved.highlightedRow(in: engine().rows(for: "")) == nil)
    }
}
