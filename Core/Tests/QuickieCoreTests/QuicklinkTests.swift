import Foundation
import Testing
@testable import QuickieCore

// A Quicklink is now a *static* URL only (CONTEXT.md → Quicklink; ADR 0013): it
// opens directly, consumes no typed text, and carries no `{placeholder}`. The
// query-consuming behaviour has moved to the Custom Action. These tests pin the
// single-shape Quicklink and the validation that keeps a placeholder out of one.
struct QuicklinkTests {

    @Test("a Quicklink opens its static URL directly")
    func opensDirectly() {
        let link = Action.quicklink(
            id: "apple",
            title: "Open Apple",
            url: URL(string: "https://apple.com")!
        )
        #expect(link.run() == .openURL(URL(string: "https://apple.com")!))
    }

    @Test("a Quicklink consumes no typed text")
    func consumesNoInput() {
        let link = Action.quicklink(id: "a", title: "Apple", url: URL(string: "https://apple.com")!)
        #expect(link.inputTypes.isEmpty)
        // Even handed input, a static link ignores it and opens as stored.
        #expect(link.run(input: "ignored") == .openURL(URL(string: "https://apple.com")!))
    }

    @Test("a Quicklink is never a Fallback")
    func neverFallback() {
        let link = Action.quicklink(id: "a", title: "Apple", url: URL(string: "https://apple.com")!)
        #expect(link.isFallback == false)
        #expect(link.kind == .quicklink)
    }

    @Test("placeholder detection rejects a templated URL from the Quicklinks editor")
    func placeholderDetection() {
        // The Quicklinks editor uses this to reject a `{placeholder}` (a Quicklink
        // is static); the Fallbacks editor uses it to *require* one.
        #expect(Action.templateContainsPlaceholder("https://github.com/search?q={query}"))
        #expect(Action.templateContainsPlaceholder("https://example.com/{term}/page"))
        #expect(Action.templateContainsPlaceholder("https://apple.com") == false)
        // An empty brace pair isn't a real placeholder token.
        #expect(Action.templateContainsPlaceholder("https://x.com/{}") == false)
    }
}
