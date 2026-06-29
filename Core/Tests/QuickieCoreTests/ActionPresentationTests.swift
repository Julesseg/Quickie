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

    @Test("a Fallback query is a distinct provider kind from a plain Quicklink")
    func fallbackQueryKindIsDistinctFromQuicklink() {
        // Both open the browser, so the leading badge can only tell them apart by
        // provider identity, not by what they do.
        let search = Action.webSearchFallback()
        let link = Action.quicklink(id: "q1", title: "GitHub", url: URL(string: "https://github.com")!)
        #expect(search.kind == .fallbackQuery)
        #expect(link.kind == .quicklink)
    }

    @Test("each main action reads off the row's real outcome")
    func mainActionFollowsOutcome() {
        #expect(Action.quicklink(id: "q", title: "GitHub", url: URL(string: "https://github.com")!).mainAction == .openInBrowser)
        #expect(Action.note(id: "n", title: "Idea").mainAction == .openNote)
        #expect(Action.newNote().mainAction == .compose)
        #expect(Action.newSnippet().mainAction == .compose)
        #expect(Action.openNotesLibrary().mainAction == .openPage)
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

    @Test("New Snippet opens the snippet editor seeded with the typed text")
    func newSnippetComposesSeeded() {
        let action = Action.newSnippet()
        #expect(action.isFallback)
        #expect(action.kind == .newSnippet)
        #expect(action.run(input: "Hello from Quickie") == .composeSnippet(seed: "Hello from Quickie"))
    }

    @Test("the management commands open their full-screen pages")
    func managementCommandsOpenPages() {
        #expect(Action.openNotesLibrary().run() == .openPage(.notes))
        #expect(Action.openSnippetsLibrary().run() == .openPage(.snippets))
        #expect(Action.openSettings().run() == .openPage(.settings))
        #expect(Action.openQuicklinksPage().run() == .openPage(.quicklinks))
        #expect(Action.openFallbacksPage().run() == .openPage(.fallbacks))
        // Commands, not Fallbacks — they match by name and don't ride the bottom.
        #expect(Action.openNotesLibrary().isFallback == false)
        #expect(Action.openSettings().isFallback == false)
    }
}
