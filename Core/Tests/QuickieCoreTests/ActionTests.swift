import Foundation
import Testing
@testable import QuickieCore

// An Action is the one kind of thing in the index. These tests pin two
// promises: every Action declares typed input/output content (ADR 0011, so a
// future Workflow can chain them), and tapping a row runs its *main action*,
// which is observable as an ActionOutcome the platform layer performs.
struct ActionTests {

    @Test("a static link's main action opens its URL")
    func staticLinkOpensURL() {
        let github = Action.quicklink(
            id: "github",
            title: "Open GitHub",
            url: URL(string: "https://github.com")!
        )
        #expect(github.run() == .openURL(URL(string: "https://github.com")!))
    }

    @Test("a static link declares url output and consumes no input")
    func staticLinkTypedContent() {
        let github = Action.quicklink(
            id: "github",
            title: "Open GitHub",
            url: URL(string: "https://github.com")!
        )
        #expect(github.outputType == .url)
        #expect(github.inputTypes.isEmpty)
    }

    @Test("a Fallback query fills the typed text into its template")
    func fallbackQueryConsumesInput() {
        let search = Action.fallbackQuery(
            id: "web-search",
            title: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        )
        #expect(search?.run(input: "swift testing")
                == .openURL(URL(string: "https://duckduckgo.com/?q=swift%20testing")!))
    }

    @Test("a Fallback query declares text input and url output")
    func fallbackQueryTypedContent() {
        let search = Action.fallbackQuery(
            id: "web-search",
            title: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        )
        #expect(search?.inputTypes == [.text])
        #expect(search?.outputType == .url)
    }
}
