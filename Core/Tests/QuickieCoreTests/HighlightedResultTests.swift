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
        SearchEngine(providers: [
            IndexedProvider(catalog: [
                .quicklink(id: "github", title: "Open GitHub", aliases: ["git"], url: URL(string: "https://github.com")!),
                .webSearchFallback(),
            ])
        ])
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
        // "qwerty" matches nothing by name; the web-search Fallback query is the
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
    }

    @Test("a multi-step capture row reads as .go — Enter begins the capture")
    func goLabelForMultiStepCapture() {
        // New Reminder collects Arguments through the breadcrumb; its plain `run()`
        // outcome is `.none`, so the label must come from its having Arguments, not
        // the outcome — Enter on the highlighted row starts the capture.
        #expect(Action.newReminder().returnKeyLabel == .go)
    }
}
