import Foundation
import Testing
@testable import QuickieCore

// A Quicklink is a stored URL *template* with zero or more `{placeholder}`
// tokens (CONTEXT.md → Quicklink). The same stored field drives both shapes:
// no placeholder → opens directly; a placeholder → takes the typed text as its
// Argument. These tests pin that one-field, auto-detecting behavior — the model
// the SwiftData store persists and the manage UI edits.
struct QuicklinkTests {

    @Test("a template with no placeholder opens its URL directly")
    func staticTemplateOpensDirectly() {
        let link = Action.quicklink(
            id: "apple",
            title: "Open Apple",
            template: "https://apple.com"
        )
        #expect(link.run() == .openURL(URL(string: "https://apple.com")!))
    }

    @Test("a template with a placeholder fills the typed text as its Argument")
    func placeholderTemplateFillsTypedText() {
        let link = Action.quicklink(
            id: "gh-search",
            title: "Search GitHub",
            template: "https://github.com/search?q={query}"
        )
        #expect(link.run(input: "swift testing")
                == .openURL(URL(string: "https://github.com/search?q=swift%20testing")!))
    }

    @Test("any placeholder name is detected, not just {query}")
    func anyPlaceholderNameWorks() {
        let link = Action.quicklink(
            id: "dict",
            title: "Define",
            template: "https://example.com/define/{term}"
        )
        #expect(link.inputTypes == [.text])
        #expect(link.run(input: "ephemeral")
                == .openURL(URL(string: "https://example.com/define/ephemeral")!))
    }

    @Test("a static template declares no input; a placeholder declares text")
    func templateTypedContent() {
        let staticLink = Action.quicklink(id: "a", title: "Apple", template: "https://apple.com")
        let placeholder = Action.quicklink(id: "s", title: "Search", template: "https://q/?x={q}")
        #expect(staticLink.inputTypes.isEmpty)
        #expect(placeholder.inputTypes == [.text])
    }

    @Test("placeholder detection drives the static-vs-Argument decision")
    func placeholderDetection() {
        #expect(Action.templateHasPlaceholder("https://github.com/search?q={query}"))
        #expect(Action.templateHasPlaceholder("https://example.com/{term}/page"))
        #expect(Action.templateHasPlaceholder("https://apple.com") == false)
        // An empty brace pair isn't a real placeholder token.
        #expect(Action.templateHasPlaceholder("https://x.com/{}") == false)
    }
}
