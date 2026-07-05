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
}
