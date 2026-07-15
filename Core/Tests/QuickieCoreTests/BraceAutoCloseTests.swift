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

    @Test("a coalesced keystroke burst ending in { auto-closes like a lone {")
    func coalescedBurstEndingInOpenBraceAutoCloses() {
        // Fast typing (and XCUITest's synthesized bursts) reaches the binding as
        // one multi-character insertion — the rule keys on the run's last char.
        #expect(
            BraceAutoClose.adjusted(replacing: "", with: "app://x?a={")
                == "app://x?a={}"
        )
    }

    @Test("a coalesced burst ending in } skips over the close sitting after the caret")
    func coalescedBurstSkipsOverAutoClose() {
        // After the auto-close the caret sits between the braces; a coalesced
        // "title}" burst lands before the auto-inserted `}` and its own close
        // collapses onto it.
        #expect(
            BraceAutoClose.adjusted(replacing: "app://x?a={}", with: "app://x?a={title}}")
                == "app://x?a={title}"
        )
    }

    @Test("a burst ending in } after a completed token is kept — no skip-over backwards")
    func coalescedBurstAfterCompletedTokenPassesThrough() {
        // Only a lone `}` skips against the `}` *before* it (its insertion spot
        // is ambiguous); a longer run's preceding `}` is just a finished token,
        // so appending the next `&x={y}` chunk must keep its final close.
        #expect(BraceAutoClose.adjusted(replacing: "a?t={x}", with: "a?t={x}&n={y}") == nil)
    }

    @Test("a balanced multi-character paste passes through untouched")
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
