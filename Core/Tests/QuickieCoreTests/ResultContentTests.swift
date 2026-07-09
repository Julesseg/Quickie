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

    @Test("a snippet declares snippet content, keyed by its id")
    func snippetContentIsSnippet() {
        // A Snippet declares `.snippet(id:)`, not the bare `.text` its copy
        // outcome would derive — the id is what lets the menu add Edit (ADR 0017).
        let snippet = Action.snippet(id: "s1", title: "Address", body: "1 Infinite Loop")
        #expect(snippet.content == .snippet(id: "s1"))
    }

    @Test("a Pile entry declares its text content, keyed by the entry's id")
    func pileEntryContentIsItsText() {
        let entry = Action.pileEntry(id: "pile.42", text: "groceries for the week")
        #expect(entry.content == .pileEntry(id: "pile.42"))
    }

    @Test("a quicklink declares quicklink content, keyed by its id")
    func quicklinkContentIsQuicklink() {
        // A Quicklink declares `.quicklink(id:)`, not the bare `.url` its open
        // outcome would derive — the id is what lets the menu add Edit (open its
        // create/edit form) on top of copy/share (ADR 0017).
        let link = Action.quicklink(id: "gh", title: "GitHub", url: URL(string: "https://github.com")!)
        #expect(link.content == .quicklink(id: "gh"))
    }

    @Test("a quicklink offers copy + share + Edit via its declared content")
    func quicklinkOffersCopyShareEdit() {
        // A Quicklink still carries a real URL to copy or share, and its stored
        // identity adds Edit — the Snippet pattern for a URL; the deeplink sits last.
        let link = Action.quicklink(id: "gh", title: "GitHub", url: URL(string: "https://github.com")!)
        #expect(secondaryActions(for: link.content) == [.copy, .share, .edit, .copyDeeplink])
    }

    @Test("a Custom Action declares custom-action content, keyed by its id")
    func customActionContentIsCustomAction() {
        // A Custom Action's URL only exists once its slots are filled through the
        // breadcrumb, so — like a Shortcut hand-off — it carries no pre-resolved
        // value to copy or share (ADR 0021); but it declares `.customAction(id:)` so
        // the menu can add **Edit** (open its live-mirroring editor).
        let search = Action.webSearchFallback()
        #expect(search.content == .customAction(id: Action.webSearchFallbackID))
    }

    @Test("a Custom Action offers Edit (then the deeplink) — no value to copy or share")
    func customActionOffersEditOnly() {
        // Among the content verbs a Custom Action earns only Edit (open its editor) —
        // never copy/share, since it has no pre-resolved value — followed by the
        // universal id-keyed Copy action deeplink every row earns (issue #120).
        let search = Action.webSearchFallback()
        #expect(secondaryActions(for: search.content) == [.edit, .copyDeeplink])
    }

    @Test("a file declares file content, carrying its bookmark + relative path")
    func fileContentIsFile() {
        let file = Action.file(bookmarkID: "folder-1", relativePath: "docs/report.pdf")
        #expect(file.content == .file(bookmarkID: "folder-1", relativePath: "docs/report.pdf"))
    }

    @Test("a command row carries no content, so it exposes only the deeplink verb")
    func commandRowHasNoContent() {
        // A Settings command is `.text`-typed but carries no value — exactly the
        // case a type-keyed table could not tell apart from a text Snippet. It earns
        // no content verbs, only the id-keyed Copy action deeplink (issue #120).
        let settings = Action.openSettings()
        #expect(settings.content == .none)
        #expect(secondaryActions(for: settings.content) == [.copyDeeplink])
    }

    @Test("a Shortcut declares shortcut content, keyed by its name")
    func shortcutContentIsShortcut() {
        // A Shortcut declares `.shortcut(name:)`, not the `.none` its run outcome
        // would derive — the name is what lets the menu add Edit, a deeplink into
        // the Shortcuts app's editor (ADR 0017).
        let shortcut = Action.shortcut(name: "Do Thing")
        #expect(shortcut.content == .shortcut(name: "Do Thing"))
    }

    @Test("a Shortcut offers Edit (then the deeplink) — no text to copy or share")
    func shortcutOffersEditOnly() {
        // A Shortcut is a launchable reference, not a value, so among the content
        // verbs it earns only Edit (open the named shortcut in the Shortcuts app) —
        // never copy/share — followed by the universal Copy action deeplink.
        let shortcut = Action.shortcut(name: "Do Thing")
        #expect(secondaryActions(for: shortcut.content) == [.edit, .copyDeeplink])
    }

    @Test("acting on a Pile entry offers copy + share via its declared content")
    func actOnPileEntryOffersCopyShare() {
        let entry = Action.pileEntry(id: "pile.7", text: "ideas for the offsite")
        #expect(secondaryActions(for: entry.content) == [.copy, .share, .copyDeeplink])
    }

    @Test("a snippet additionally offers Edit via its declared content")
    func snippetOffersEdit() {
        // The Edit verb rides a Snippet's `.snippet(id:)` content on top of the
        // universal copy/share, distinguishing it from a value-only `.text` row; the
        // id-keyed Copy action deeplink follows last.
        let snippet = Action.snippet(id: "snip.1", title: "Address", body: "1 Infinite Loop")
        #expect(secondaryActions(for: snippet.content) == [.copy, .share, .edit, .copyDeeplink])
    }
}
