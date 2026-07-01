import Foundation
import Testing
@testable import QuickieCore

// Every result row carries two glyphs (issue #11 follow-up): a leading
// provider badge — what kind of thing this is (Quicklink, Snippet, Pile…) — and
// a trailing main-action glyph — what tapping it does (open in browser, copy,
// stage). Both are pure classifications of the Action, so the App renders icons
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
        #expect(Action.pileEntry(id: "p", text: "look into e-bike rebates").mainAction == .stage)
        #expect(Action.saveForLater().mainAction == .saveToPile)
        #expect(Action.newSnippet().mainAction == .compose)
        #expect(Action.openPilePage().mainAction == .openPage)
        #expect(Action.file(bookmarkID: "f", relativePath: "a/b.txt").mainAction == .openFile)
    }

    @Test("a file is its own provider kind and opens on Enter")
    func fileKindAndReturnKey() {
        let file = Action.file(bookmarkID: "f", relativePath: "a/report.pdf")
        #expect(file.kind == .file)
        // Enter on a highlighted file row opens it — the `.go` submit label.
        #expect(file.returnKeyLabel == .go)
    }

    @Test("a multi-step capture's glyph reads its final outcome, not its empty effect")
    func multiStepMainActionFollowsFinalOutcome() {
        // New Reminder collects its Arguments before producing anything, so its
        // plain `run()` is the placeholder `.none`; the trailing glyph must still
        // read the capture's real outcome (`createReminder` → compose), so the row
        // wears the same compose pencil as New Snippet rather than no glyph at all.
        #expect(Action.newReminder().mainAction == .compose)
        #expect(Action.newReminder(askDate: false, list: .ask, lists: [
            ChoiceOption(id: "work", label: "Work"),
        ]).mainAction == .compose)

        // New Event is the same story: it produces nothing until its breadcrumb is
        // collected, so both the silent (`createEvent`) and editor (`composeEvent`)
        // outcomes classify as compose — the row wears the compose pencil either way.
        #expect(Action.newEvent().mainAction == .compose)
        #expect(Action.newEvent(editor: true).mainAction == .compose)
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
        #expect(Action.openPilePage().run() == .openPage(.pile))
        #expect(Action.openSnippetsLibrary().run() == .openPage(.snippets))
        #expect(Action.openSettings().run() == .openPage(.settings))
        #expect(Action.openQuicklinksPage().run() == .openPage(.quicklinks))
        #expect(Action.openFallbacksPage().run() == .openPage(.fallbacks))
        #expect(Action.openIndexedFoldersPage().run() == .openPage(.indexedFolders))
        // Commands, not Fallbacks — they match by name and don't ride the bottom.
        #expect(Action.openPilePage().isFallback == false)
        #expect(Action.openSettings().isFallback == false)
    }
}
