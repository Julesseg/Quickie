import Testing
@testable import QuickieCore

// The URL-template field's brace typing rules (CONTEXT.md → Custom Action): pure
// before/after text pairs, so the keyboard-order edge cases — pastes, deletions,
// adjacent braces, typing a whole `{token}` by hand — are pinned down without a
// device. The editor replays these onto the field binding per keystroke.
struct BraceAutoCloseTests {

    @Test("typing { auto-closes the pair, with the close behind the caret")
    func openingBraceAutoCloses() {
        #expect(
            BraceAutoClose.adjusted(replacing: "things:///add?title=", with: "things:///add?title={")
                == "things:///add?title={}"
        )
    }

    @Test("typing { mid-text closes in place, not at the end")
    func openingBraceMidTextClosesInPlace() {
        #expect(BraceAutoClose.adjusted(replacing: "a?q=&b=2", with: "a?q={&b=2") == "a?q={}&b=2")
    }

    @Test("typing } over the auto-inserted close skips it instead of doubling")
    func closingBraceSkipsOverAutoClose() {
        // The caret sits before the auto-inserted `}` after typing the name; the
        // user's own `}` collapses back to the unchanged text, so a full hand-typed
        // `{title}` lands exactly one pair.
        #expect(BraceAutoClose.adjusted(replacing: "a?q={title}", with: "a?q={title}}") == "a?q={title}")
    }

    @Test("typing } with no adjacent close is kept as typed")
    func closingBraceWithoutNeighborPassesThrough() {
        // e.g. closing a pasted, unclosed `{a` by hand.
        #expect(BraceAutoClose.adjusted(replacing: "a?q={a", with: "a?q={a}") == nil)
    }

    @Test("typing { right before an existing } re-opens the pair, no double close")
    func openingBraceBeforeExistingCloseDoesNotDouble() {
        #expect(BraceAutoClose.adjusted(replacing: "a?q=}", with: "a?q={}") == nil)
    }

    @Test("a multi-character paste passes through untouched")
    func pastePassesThrough() {
        #expect(BraceAutoClose.adjusted(replacing: "", with: "things:///add?title={title}") == nil)
    }

    @Test("a deletion passes through untouched")
    func deletionPassesThrough() {
        // Also the editor's own rule-2 rewrite (new → old) re-enters as a deletion —
        // it must not trigger anything.
        #expect(BraceAutoClose.adjusted(replacing: "a?q={}", with: "a?q={") == nil)
    }

    @Test("a non-brace keystroke passes through untouched")
    func ordinaryTypingPassesThrough() {
        #expect(BraceAutoClose.adjusted(replacing: "a?q={}", with: "a?q={t}") == nil)
    }
}
