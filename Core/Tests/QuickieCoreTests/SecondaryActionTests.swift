import Foundation
import Testing
@testable import QuickieCore

// Secondary actions are a one-shot long-press affordance keyed by a result's
// *content* — its value/reference — not its content *type* (ADR 0017,
// CONTEXT.md → Secondary action / Result content). Eligibility is a pure
// function of `ResultContent`, so a content-less row (command / capture /
// shortcut) exposes none even though it may carry a `text` output type. These
// tests pin that switch; execution and edge-resolution live in the App.
struct SecondaryActionTests {

    @Test("a content-less result exposes no secondary actions")
    func noneExposesNothing() {
        #expect(secondaryActions(for: .none) == [])
    }

    @Test("a text-bearing result exposes the universal copy + share")
    func textBearingExposesCopyShare() {
        #expect(secondaryActions(for: .text) == [.copy, .share])
    }

    @Test("a url and a number expose copy + share, same as text")
    func urlAndNumberExposeCopyShare() {
        #expect(secondaryActions(for: .url) == [.copy, .share])
        #expect(secondaryActions(for: .number) == [.copy, .share])
    }

    @Test("a Note body exposes copy + share (act on a Note)")
    func noteBodyExposesCopyShare() {
        #expect(secondaryActions(for: .noteBody(id: "note.1")) == [.copy, .share])
    }

    @Test("a file additionally exposes reveal in Files")
    func fileAlsoExposesReveal() {
        #expect(
            secondaryActions(for: .file(bookmarkID: "folder-1", relativePath: "docs/report.pdf"))
                == [.copy, .share, .revealInFiles]
        )
    }
}
