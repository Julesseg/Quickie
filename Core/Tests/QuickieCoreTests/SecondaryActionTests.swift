import Foundation
import Testing
@testable import QuickieCore

// Secondary actions are a one-shot long-press affordance (ADR 0017, CONTEXT.md →
// Secondary action / Result content). The content-keyed verbs (copy/share/edit/
// reveal) are a pure function of `ResultContent` — a content-less row (a command
// or capture) exposes none of them even though it may carry a `text` output type,
// while a Shortcut — a launchable reference — exposes Edit alone. On top of those,
// one id-keyed verb, `copyDeeplink`, rides on *every* row (issue #120) — the lone
// verb a content-less row still exposes. These tests pin that switch; execution
// and edge-resolution live in the App.
struct SecondaryActionTests {

    @Test("a content-less result exposes only Copy action deeplink")
    func noneExposesOnlyDeeplink() {
        // The content-keyed verbs still exclude a command/capture row; the id-keyed
        // Copy action deeplink is the one verb it earns, since every row has an id.
        #expect(secondaryActions(for: .none) == [.copyDeeplink])
    }

    @Test("a text-bearing result exposes copy + share, then the deeplink")
    func textBearingExposesCopyShare() {
        #expect(secondaryActions(for: .text) == [.copy, .share, .copyDeeplink])
    }

    @Test("a url and a number expose copy + share + deeplink, same as text")
    func urlAndNumberExposeCopyShare() {
        #expect(secondaryActions(for: .url) == [.copy, .share, .copyDeeplink])
        #expect(secondaryActions(for: .number) == [.copy, .share, .copyDeeplink])
    }

    @Test("a Pile entry's text exposes copy + share + deeplink")
    func pileEntryExposesCopyShare() {
        #expect(secondaryActions(for: .pileEntry(id: "pile.1")) == [.copy, .share, .copyDeeplink])
    }

    @Test("a snippet additionally exposes Edit — a stored, titled record")
    func snippetAlsoExposesEdit() {
        // A Snippet is editable where a bare `.text` value is not: `.snippet`
        // carries the record's id, so the App can open the editor on it. The
        // deeplink verb sits last, after the content verbs.
        #expect(secondaryActions(for: .snippet(id: "snippet.1")) == [.copy, .share, .edit, .copyDeeplink])
    }

    @Test("a shortcut exposes Edit then the deeplink — a launchable reference, no text")
    func shortcutExposesEditThenDeeplink() {
        // A Shortcut carries no textual value to copy or share; its `.shortcut`
        // content earns only Edit — a deeplink into the Shortcuts app's editor —
        // plus the universal Copy action deeplink.
        #expect(secondaryActions(for: .shortcut(name: "Start Workout")) == [.edit, .copyDeeplink])
    }

    @Test("a file additionally exposes reveal in Files, then the deeplink")
    func fileAlsoExposesReveal() {
        #expect(
            secondaryActions(for: .file(bookmarkID: "folder-1", relativePath: "docs/report.pdf"))
                == [.copy, .share, .revealInFiles, .copyDeeplink]
        )
    }

    @Test("Copy action deeplink is always last, after any content verbs")
    func deeplinkIsAlwaysLast() {
        for content: ResultContent in [
            .none, .text, .url, .number,
            .snippet(id: "s"), .shortcut(name: "S"),
            .pileEntry(id: "p"), .file(bookmarkID: "b", relativePath: "f"),
        ] {
            #expect(secondaryActions(for: content).last == .copyDeeplink)
        }
    }
}
