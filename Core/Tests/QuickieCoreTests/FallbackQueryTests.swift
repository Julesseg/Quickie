import Foundation
import Testing
@testable import QuickieCore

// A Fallback query is a URL template that *requires* a `{placeholder}` and
// consumes the typed text as its query (CONTEXT.md → Fallback query; ADR 0013).
// It is one kind of Fallback Action, so it always rides the bottom region and is
// fed the raw typed text. These tests pin the new single-behaviour type that
// replaces the old polymorphic placeholder-Quicklink.
struct FallbackQueryTests {

    @Test("a Fallback query without a placeholder is rejected")
    func requiresPlaceholder() {
        #expect(Action.fallbackQuery(id: "x", title: "X", template: "https://x.com") == nil)
        // An empty brace pair is not a real placeholder token.
        #expect(Action.fallbackQuery(id: "y", title: "Y", template: "https://x.com/{}") == nil)
    }

    @Test("a Fallback query with a placeholder is a text-consuming Fallback")
    func placeholderMakesAFallback() {
        let query = Action.fallbackQuery(
            id: "ddg", title: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        )
        #expect(query != nil)
        #expect(query?.isFallback == true)
        #expect(query?.kind == .fallbackQuery)
        #expect(query?.inputTypes == [.text])
    }

    @Test("a Fallback query fills the typed text into its placeholder")
    func fillsTypedText() {
        let query = Action.fallbackQuery(
            id: "ddg", title: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        )
        #expect(query?.run(input: "swift testing")
                == .openURL(URL(string: "https://duckduckgo.com/?q=swift%20testing")!))
    }
}
