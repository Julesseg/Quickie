import Foundation
import Testing
@testable import QuickieCore

// Where the highlight sits in the Result list (CONTEXT.md → Highlighted result;
// issue #267). Until now the highlight *was* rank 0 — pinned there structurally —
// so "which row does Enter run?" had no state behind it. Arrow-key navigation
// needs the two decoupled: the highlight moves, the ranking does not. This is the
// whole decision, and it lives here rather than in a SwiftUI `@State` because the
// list is rendered **reversed** (ADR 0008): which way each arrow moves the
// highlight is exactly the kind of thing that quietly inverts in a view builder.
struct ResultSelectionTests {

    // MARK: - Primed on the best match

    @Test("a primed selection highlights the best match")
    func primedHighlightsRankZero() {
        #expect(ResultSelection.primed.highlightedRank(in: 5) == 0)
    }

    @Test("with no results there is no highlight at all")
    func noResultsNoHighlight() {
        #expect(ResultSelection.primed.highlightedRank(in: 0) == nil)
        #expect(ResultSelection.primed.moved(.up, resultCount: 4).highlightedRank(in: 0) == nil)
    }

    // MARK: - Which way each arrow moves

    @Test("↑ walks up the screen, toward the weaker matches")
    func upWalksTowardWeakerMatches() {
        // The list is reversed: rank 0 sits at the *bottom*, nearest the input, and
        // weaker matches stack upward. So ↑ — the key pointing up the screen —
        // moves to rank 1, 2, … exactly as the eye follows it.
        var selection = ResultSelection.primed
        selection = selection.moved(.up, resultCount: 4)
        #expect(selection.highlightedRank(in: 4) == 1)
        selection = selection.moved(.up, resultCount: 4)
        #expect(selection.highlightedRank(in: 4) == 2)
    }

    @Test("↓ walks back down toward the best match")
    func downWalksTowardTheBestMatch() {
        var selection = ResultSelection.primed
            .moved(.up, resultCount: 4)
            .moved(.up, resultCount: 4)
        #expect(selection.highlightedRank(in: 4) == 2)
        selection = selection.moved(.down, resultCount: 4)
        #expect(selection.highlightedRank(in: 4) == 1)
        selection = selection.moved(.down, resultCount: 4)
        #expect(selection.highlightedRank(in: 4) == 0)
    }

    @Test("an arrow key with nothing to move through changes nothing")
    func noResultsMakeMovesNoOps() {
        let selection = ResultSelection.primed.moved(.up, resultCount: 0)
        #expect(selection == ResultSelection.primed)
    }

    // MARK: - The ends of the list

    @Test("the highlight stops at the weakest match rather than wrapping")
    func upStopsAtTheWeakestMatch() {
        var selection = ResultSelection.primed
        for _ in 0..<10 { selection = selection.moved(.up, resultCount: 3) }
        #expect(selection.highlightedRank(in: 3) == 2)
    }

    @Test("the highlight stops at the best match rather than wrapping")
    func downStopsAtTheBestMatch() {
        var selection = ResultSelection.primed
        for _ in 0..<10 { selection = selection.moved(.down, resultCount: 3) }
        #expect(selection.highlightedRank(in: 3) == 0)
    }

    // MARK: - Typing re-primes the best match

    @Test("a walked highlight is a different selection from the primed one")
    func walkingLeavesThePrimedSelection() {
        // The launcher swaps `.primed` back in on every keystroke — typing re-ranks
        // the results, so it re-arms the best match however far ↑ had walked. That
        // is a reset on the *event* of typing, deliberately not a comparison against
        // the query text: a query walked, typed past, and backspaced back to has
        // been typed twice, and the highlight belongs at the top both times.
        let walked = ResultSelection.primed
            .moved(.up, resultCount: 6)
            .moved(.up, resultCount: 6)
        #expect(walked.highlightedRank(in: 6) == 2)
        #expect(walked != ResultSelection.primed)
        #expect(ResultSelection.primed.highlightedRank(in: 6) == 0)
    }

    // MARK: - Results moving under a walked highlight

    @Test("a shrinking result list clamps the highlight to the weakest row left")
    func shrinkingResultsClampTheHighlight() {
        let selection = ResultSelection.primed
            .moved(.up, resultCount: 6)
            .moved(.up, resultCount: 6)
            .moved(.up, resultCount: 6)
        #expect(selection.highlightedRank(in: 6) == 3)
        // Results can thin out without a keystroke — an index finishing, a provider
        // going dark. The highlight lands on the weakest row that still exists
        // rather than pointing past the end of the list.
        #expect(selection.highlightedRank(in: 2) == 1)
        #expect(selection.highlightedRank(in: 1) == 0)
        #expect(selection.highlightedRank(in: 0) == nil)
    }

    // MARK: - Reading the highlighted row

    @Test("the highlighted row is the row at the highlighted rank")
    func highlightedRowFollowsTheRank() {
        let rows = [
            ResultRow(action: .quicklink(id: "a", title: "Alpha", url: URL(string: "https://a.example")!), region: .ranked),
            ResultRow(action: .quicklink(id: "b", title: "Bravo", url: URL(string: "https://b.example")!), region: .ranked),
        ]
        #expect(ResultSelection.primed.highlightedRow(in: rows)?.action.id == "a")
        let walked = ResultSelection.primed.moved(.up, resultCount: rows.count)
        #expect(walked.highlightedRow(in: rows)?.action.id == "b")
        #expect(ResultSelection.primed.highlightedRow(in: []) == nil)
    }

    // MARK: - Claiming the keys at all

    @Test("the launcher claims ↑/↓ only when there is somewhere to move")
    func claimsArrowKeysOnlyWithSomewhereToMove() {
        #expect(ResultSelection.claimsArrowKeys(resultCount: 2, isCapturing: false))
        // One row is nowhere to go, and an unclaimed arrow keeps its own meaning —
        // moving the caret through a wrapped query — so we leave it alone.
        #expect(!ResultSelection.claimsArrowKeys(resultCount: 1, isCapturing: false))
        // Home: no results, nothing to navigate.
        #expect(!ResultSelection.claimsArrowKeys(resultCount: 0, isCapturing: false))
    }

    @Test("a capture in flight keeps the arrow keys")
    func captureKeepsTheArrowKeys() {
        // The capture owns the bottom bar and its own choice list; the Result list
        // is not on screen to walk.
        #expect(!ResultSelection.claimsArrowKeys(resultCount: 8, isCapturing: true))
    }
}
