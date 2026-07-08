import Foundation
import Testing
@testable import QuickieCore

// The Share Extension's classification rules are pure functions in Core (ADR
// 0022): the extension is a thin shell that unpacks the shared items, calls
// these, and writes through the shared store. These tests pin the URL branch
// (issue #101): what a shared URL's Quicklink is named by default, and when
// shared plain text reads as a web URL.
struct ShareClassificationTests {

    @Test("a shared URL's Quicklink name defaults to the page title when present")
    func nameDefaultsToPageTitle() {
        let name = ShareClassification.quicklinkName(
            pageTitle: "Anthropic – Home",
            url: URL(string: "https://anthropic.com")!
        )
        #expect(name == "Anthropic – Home")
    }

    @Test("without a page title the name falls back to the URL host", arguments: [nil, "", "   \n"])
    func nameFallsBackToHost(title: String?) {
        let name = ShareClassification.quicklinkName(
            pageTitle: title,
            url: URL(string: "https://news.ycombinator.com/item?id=1")!
        )
        #expect(name == "news.ycombinator.com")
    }

    @Test("a page 'title' that just restates the URL reads as no title")
    func titleRestatingTheURLReadsAsNoTitle() {
        // Some apps hand the shared URL string back as the item's title; naming
        // the Quicklink that is worse than the host default.
        let name = ShareClassification.quicklinkName(
            pageTitle: "https://example.org/a",
            url: URL(string: "https://example.org/a")!
        )
        #expect(name == "example.org")
    }

    @Test("the host default drops a bare www. prefix")
    func hostDefaultDropsWWW() {
        let name = ShareClassification.quicklinkName(
            pageTitle: nil,
            url: URL(string: "https://www.example.org/docs")!
        )
        #expect(name == "example.org")
    }

    @Test("a hostless URL falls back to the URL string itself")
    func hostlessURLFallsBackToString() {
        let name = ShareClassification.quicklinkName(
            pageTitle: nil,
            url: URL(string: "mailto:hi@example.org")!
        )
        #expect(name == "mailto:hi@example.org")
    }

    @Test("shared plain text that is a web URL reads as the URL branch")
    func sharedTextThatIsAWebURL() {
        let url = ShareClassification.webURL(fromSharedText: "https://example.org/a?b=c")
        #expect(url == URL(string: "https://example.org/a?b=c"))
    }

    @Test(
        "shared prose is not a web URL",
        arguments: [
            "buy oat milk and eggs",
            "see https://example.org for details",
            "https://",
            "",
        ]
    )
    func sharedProseIsNotAWebURL(text: String) {
        #expect(ShareClassification.webURL(fromSharedText: text) == nil)
    }

    @Test(
        "a well-formed non-web scheme is not the URL branch",
        arguments: [
            "javascript:alert(1)",
            "ftp://example.org/file",
            "shortcuts://open-shortcut",
        ]
    )
    func nonWebSchemesAreNotTheURLBranch(text: String) {
        // Pins the http(s) allowlist itself, not just "isn't a URL at all":
        // these parse fine as URLs (ftp even has a host) and must still refuse.
        #expect(ShareClassification.webURL(fromSharedText: text) == nil)
    }

    @Test("surrounding whitespace doesn't stop shared text reading as a web URL")
    func sharedTextURLTrimsSurroundingWhitespace() {
        let url = ShareClassification.webURL(fromSharedText: "  https://example.org\n")
        #expect(url == URL(string: "https://example.org"))
    }

    // The text branch (issue #102): shared plain text defaults to a Snippet,
    // whose title pre-fills from the first line of the text truncated to ~40
    // characters (a Pile entry is titleless and needs none of this). The
    // derivation is a pure Core function so `swift test` covers it, not logic
    // buried in the extension shell.

    @Test("a short single-line share becomes the Snippet title verbatim")
    func snippetTitleFromShortLine() {
        let title = ShareClassification.snippetTitle(fromSharedText: "Home address")
        #expect(title == "Home address")
    }

    @Test("only the first line of a multi-line share seeds the Snippet title")
    func snippetTitleTakesFirstLineOnly() {
        // The body carries the whole text; the title is just a one-line handle,
        // so a multi-line paste titles from its opening line alone.
        let title = ShareClassification.snippetTitle(
            fromSharedText: "Quarterly plan\n\n- ship the share extension\n- write the docs"
        )
        #expect(title == "Quarterly plan")
    }

    @Test("leading blank lines and surrounding whitespace are skipped")
    func snippetTitleSkipsLeadingBlanksAndTrims() {
        let title = ShareClassification.snippetTitle(fromSharedText: "\n  \n   Buy oat milk   \n")
        #expect(title == "Buy oat milk")
    }

    @Test("a long first line is capped near 40 characters at a word boundary")
    func snippetTitleCapsAtWordBoundary() {
        // "~40 chars" — cut back to the last whole word within the limit rather
        // than slicing a word in half, so the pre-filled title reads cleanly.
        let title = ShareClassification.snippetTitle(
            fromSharedText: "The quick brown fox jumps over the lazy dog by the river"
        )
        #expect(title == "The quick brown fox jumps over the lazy")
        #expect(title.count <= 40)
    }

    @Test("a first word longer than the cap is hard-truncated at 40 characters")
    func snippetTitleHardCutsAnOverlongWord() {
        // No word boundary to fall back to, so the only option is a hard cut —
        // still bounded, never the whole 60-character monster.
        let title = ShareClassification.snippetTitle(
            fromSharedText: "Supercalifragilisticexpialidocioussuperlongword tail"
        )
        #expect(title.count == 40)
        #expect(title == "Supercalifragilisticexpialidocioussuperl")
    }

    @Test("blank or whitespace-only shared text yields an empty title", arguments: ["", "   ", "\n\n  \n"])
    func snippetTitleEmptyForBlankText(text: String) {
        // Nothing to derive: the sheet shows an empty, editable title field and
        // the Save gate keeps the user from saving a titleless Snippet.
        #expect(ShareClassification.snippetTitle(fromSharedText: text) == "")
    }

    // Routing the whole payload (issue #102 follow-up): highlight-and-share in
    // Safari activates the extension via NSExtensionActivationSupportsText but
    // *also* hands over the page URL as a public.url attachment. If the URL is
    // taken first, the user's selected text is lost to the Quicklink branch — so
    // a genuine text selection must win over the incidental page link. This is a
    // pure Core decision so `swift test` pins it, not the untested shell.

    @Test("a text selection wins over the page URL that rides along with it")
    func selectionWinsOverTheRidealongPageURL() {
        // Safari's highlight-share: the selected prose *and* the page's link.
        // The user highlighted text — that's the intent; the link is incidental.
        let route = ShareClassification.route(
            sharedText: "the mitochondria is the powerhouse of the cell",
            attachedURL: URL(string: "https://en.wikipedia.org/wiki/Mitochondrion")
        )
        #expect(route == .text("the mitochondria is the powerhouse of the cell"))
    }

    @Test("a shared string that is itself a web URL still routes to the Quicklink branch")
    func sharedURLStringRoutesToQuicklinkEvenWithAnAttachment() {
        // A plain page share whose only "text" is the URL string still becomes a
        // Quicklink — routed from the text, not the attachment, but same branch.
        let route = ShareClassification.route(
            sharedText: "https://example.org/a",
            attachedURL: URL(string: "https://example.org/a")
        )
        #expect(route == .quicklink(URL(string: "https://example.org/a")!))
    }

    @Test("a page share with no selection routes to the Quicklink branch via the URL attachment", arguments: [nil, "", "   \n"])
    func pageShareWithoutSelectionUsesTheURLAttachment(sharedText: String?) {
        let route = ShareClassification.route(
            sharedText: sharedText,
            attachedURL: URL(string: "https://anthropic.com")
        )
        #expect(route == .quicklink(URL(string: "https://anthropic.com")!))
    }

    @Test("a text selection with no URL attachment routes to the text branch")
    func selectionWithoutURLRoutesToText() {
        let route = ShareClassification.route(sharedText: "buy oat milk", attachedURL: nil)
        #expect(route == .text("buy oat milk"))
    }

    @Test("an empty payload is unsupported", arguments: [nil, "", "  \n "])
    func emptyPayloadIsUnsupported(sharedText: String?) {
        #expect(ShareClassification.route(sharedText: sharedText, attachedURL: nil) == .unsupported)
    }
}
