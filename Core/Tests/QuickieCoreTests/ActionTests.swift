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

    @Test("a Custom Action fills its collected Argument into the template")
    func customActionFillsTemplate() {
        let search = CustomActionDefinition(
            name: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        ).makeAction(id: "web-search")!
        var session = MultiStepAction(action: search)
        #expect(session.commit(.text("swift testing"))
                == .completed(.openURL(URL(string: "https://duckduckgo.com/?q=swift%20testing")!)))
    }

    @Test("a Custom Action declares text input and url output")
    func customActionTypedContent() {
        let search = CustomActionDefinition(
            name: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        ).makeAction(id: "web-search")
        #expect(search?.inputTypes == [.text])
        #expect(search?.outputType == .url)
    }

    @Test("a file's main action carries only its bookmark identity + relative path")
    func fileOpensViaBookmarkIdentity() {
        // Core never touches the filesystem (ADR 0015): a file Action resolves to a
        // pure `.openFile` outcome the app turns into a security-scoped open.
        let file = Action.file(bookmarkID: "folder-1", relativePath: "docs/report.pdf")
        #expect(file.run() == .openFile(bookmarkID: "folder-1", relativePath: "docs/report.pdf"))
    }

    @Test("a file declares file output and consumes no typed input")
    func fileTypedContent() {
        let file = Action.file(bookmarkID: "folder-1", relativePath: "docs/report.pdf")
        #expect(file.outputType == .file)
        #expect(file.inputTypes.isEmpty)
        #expect(file.isFallbackEligible == false)
    }

    @Test("a file's display name defaults to the relative path's last component")
    func fileDisplayNameDefaultsToBasename() {
        let file = Action.file(bookmarkID: "folder-1", relativePath: "docs/report.pdf")
        #expect(file.title == "report.pdf")
        // An explicit display name overrides the derived basename.
        let named = Action.file(bookmarkID: "folder-1", relativePath: "docs/report.pdf", displayName: "Q3 Report")
        #expect(named.title == "Q3 Report")
    }

    @Test("two files under different folders are distinct index entries")
    func fileIdentityFolds_bookmarkAndPath() {
        // Same relative path in two granted folders must not collide into one row.
        let a = Action.file(bookmarkID: "folder-a", relativePath: "notes.txt")
        let b = Action.file(bookmarkID: "folder-b", relativePath: "notes.txt")
        #expect(a.id != b.id)
    }
}
