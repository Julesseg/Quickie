import Foundation
import Testing
@testable import QuickieCore

// Every result row carries two glyphs (issue #11 follow-up): a leading
// provider badge — what kind of thing this is (Quicklink, Snippet, Note…) — and
// a trailing main-action glyph — what tapping it does (open in browser, copy,
// read). Both are pure classifications of the Action, so the App renders icons
// without re-deriving intent: `kind` is the provider identity and `mainAction`
// is read straight off the Action's real outcome, so the trailing glyph can
// never drift from what the row actually does.
struct ActionPresentationTests {

    @Test("a snippet's main action is copy-to-clipboard, from its real outcome")
    func snippetMainActionIsCopy() {
        let snippet = Action.snippet(id: "s1", title: "Address", body: "1 Infinite Loop")
        #expect(snippet.mainAction == .copyToClipboard)
    }

    @Test("a web-search Fallback is a distinct provider kind from a plain Quicklink")
    func webSearchKindIsDistinctFromQuicklink() {
        // Both open the browser, so the leading badge can only tell them apart by
        // provider identity, not by what they do.
        let search = Action.webSearch()
        let link = Action.quicklink(id: "q1", title: "GitHub", template: "https://github.com")
        #expect(search.kind == .webSearch)
        #expect(link.kind == .quicklink)
    }

    @Test("each main action reads off the row's real outcome")
    func mainActionFollowsOutcome() {
        #expect(Action.quicklink(id: "q", title: "GitHub", template: "https://github.com").mainAction == .openInBrowser)
        #expect(Action.note(id: "n", title: "Idea").mainAction == .openNote)
        #expect(Action.newNote().mainAction == .captureNote)
    }

    @Test("provider kind and main action are independent axes")
    func kindAndMainActionAreIndependent() {
        // A calculator result and a snippet both *copy* (same main action) but are
        // different providers (different leading badge) — so the row needs both
        // classifications, not one standing in for the other.
        let calc = CalculatorProvider().candidates(for: "2+2").first
        let snippet = Action.snippet(id: "s", title: "Reply", body: "thanks!")
        #expect(calc?.mainAction == .copyToClipboard)
        #expect(snippet.mainAction == .copyToClipboard)
        #expect(calc?.kind == .calculator)
        #expect(snippet.kind == .snippet)
    }
}
