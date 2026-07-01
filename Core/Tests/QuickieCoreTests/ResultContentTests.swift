import Foundation
import Testing
@testable import QuickieCore

// `ResultContent` is a **declared** property of every Action (ADR 0017), set
// per factory — not derived from the main-action outcome. It is what the
// long-press menu keys its secondary actions off, distinct from `mainAction`
// (which classifies the outcome). These tests pin the content each factory
// declares, and prove a content-less command exposes no secondary actions
// while content-bearing rows do.
struct ResultContentTests {

    @Test("a snippet declares text content")
    func snippetContentIsText() {
        let snippet = Action.snippet(id: "s1", title: "Address", body: "1 Infinite Loop")
        #expect(snippet.content == .text)
    }

    @Test("a Pile entry declares its text content, keyed by the entry's id")
    func pileEntryContentIsItsText() {
        let entry = Action.pileEntry(id: "pile.42", text: "groceries for the week")
        #expect(entry.content == .pileEntry(id: "pile.42"))
    }

    @Test("a quicklink declares url content")
    func quicklinkContentIsURL() {
        let link = Action.quicklink(id: "gh", title: "GitHub", url: URL(string: "https://github.com")!)
        #expect(link.content == .url)
    }

    @Test("a Fallback query result declares url content")
    func fallbackQueryContentIsURL() {
        let search = Action.fallbackQuery(
            id: "web-search",
            title: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        )
        #expect(search?.content == .url)
    }

    @Test("a file declares file content, carrying its bookmark + relative path")
    func fileContentIsFile() {
        let file = Action.file(bookmarkID: "folder-1", relativePath: "docs/report.pdf")
        #expect(file.content == .file(bookmarkID: "folder-1", relativePath: "docs/report.pdf"))
    }

    @Test("a command row carries no content, so it exposes no secondary actions")
    func commandRowHasNoContent() {
        // A Settings command is `.text`-typed but carries no value — exactly the
        // case a type-keyed table could not tell apart from a text Snippet.
        let settings = Action.openSettings()
        #expect(settings.content == .none)
        #expect(secondaryActions(for: settings.content) == [])
    }

    @Test("a Shortcut row carries no content even though it is text-typed")
    func shortcutRowHasNoContent() {
        let shortcut = Action.shortcut(name: "Do Thing")
        #expect(shortcut.content == .none)
        #expect(secondaryActions(for: shortcut.content) == [])
    }

    @Test("acting on a Pile entry offers copy + share via its declared content")
    func actOnPileEntryOffersCopyShare() {
        let entry = Action.pileEntry(id: "pile.7", text: "ideas for the offsite")
        #expect(secondaryActions(for: entry.content) == [.copy, .share])
    }
}
