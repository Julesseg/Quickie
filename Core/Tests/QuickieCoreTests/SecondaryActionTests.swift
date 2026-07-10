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

    @Test("includeDeeplink:false drops Copy action deeplink — Save for later's is a no-op")
    func silentCaptureOmitsDeeplink() {
        // Save for later does nothing run standalone (its silent Pile write; issue #140),
        // so its `quickie://run/<id>` is a no-op not worth copying: the App passes
        // includeDeeplink:false, leaving that content-less row with no verbs at all.
        #expect(secondaryActions(for: .none, includeDeeplink: false) == [])
        // The gate is orthogonal to the content verbs — a hypothetical value row with
        // the flag off keeps copy/share, just not the deeplink.
        #expect(secondaryActions(for: .text, includeDeeplink: false) == [.copy, .share])
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

    @Test("a quicklink additionally exposes Edit — a stored, editable link")
    func quicklinkAlsoExposesEdit() {
        // A Quicklink is a stored, titled static link the user can revise, so it
        // earns Edit on top of the universal copy/share (it still carries a real URL
        // to copy or share) — the Snippet pattern, for a URL. Deeplink last.
        #expect(secondaryActions(for: .quicklink(id: "ql.1")) == [.copy, .share, .edit, .copyDeeplink])
    }

    @Test("a Custom Action exposes Edit then the deeplink — an editable reference, no value")
    func customActionExposesEditThenDeeplink() {
        // A Custom Action's URL only exists once its slots are filled, so — like a
        // Shortcut — it carries no value to copy or share; its `.customAction` content
        // earns only Edit (open its live-mirroring editor), plus the universal deeplink.
        #expect(secondaryActions(for: .customAction(id: "ca.1")) == [.edit, .copyDeeplink])
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
            .quicklink(id: "ql"), .customAction(id: "ca"),
            .pileEntry(id: "p"), .file(bookmarkID: "b", relativePath: "f"),
        ] {
            #expect(secondaryActions(for: content).last == .copyDeeplink)
        }
    }
}
