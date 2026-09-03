import Foundation

/// Where the **Highlighted result** sits in the [[Result list]] (CONTEXT.md →
/// Highlighted result; issue #267) — the one piece of state that separates "the
/// row Enter runs" from "the best match".
///
/// Until arrow keys, the two were the same thing: the highlight was rank 0,
/// pinned there structurally, so there was nothing to hold. A hardware keyboard
/// needs them decoupled — **the selection moves, the ranking does not** — and
/// this is the whole of that decision.
///
/// It lives in Core rather than in a SwiftUI `@State` because of which way each
/// arrow moves, which is exactly the kind of thing that quietly inverts inside a
/// view builder: the Result list is rendered **reversed** (ADR 0008), best match
/// at the *bottom* nearest the input and the thumb, with weaker matches stacking
/// upward. So the arrow that walks toward the second-best match is ↑, not ↓ — the
/// opposite of the mapping every other list has. Here it is one asserted invariant
/// instead of a `+ 1` in a view builder.
///
/// The value is a plain rank, with no query and no results attached, so it cannot
/// disagree with either. The App replaces it with `.primed` on every keystroke —
/// typing re-ranks the results, so it re-arms the best match — and that is a reset
/// on the *event* of typing, deliberately not a comparison against the query text:
/// a query walked, typed past, and then backspaced back to is a query the user has
/// typed twice, and the highlight belongs at the top both times. Reads resolve
/// against the *current* result count too, which is what keeps a highlight walked
/// deep into a long list from pointing past the end of a short one.
public struct ResultSelection: Equatable, Sendable {

    /// A hardware arrow key, named for the direction it points **on screen** — the
    /// only direction the user is thinking in. `moved(_:resultCount:)` owns the
    /// translation into ranks, reversal and all.
    public enum ArrowKey: Equatable, Sendable {
        case up
        case down
    }

    /// The highlight as typing leaves it: on the best match, ready for Return.
    ///
    /// This is the only way to make a selection, because it is the only state a
    /// selection is ever in that an arrow key did not reach — the launcher's
    /// starting value, and what it swaps back in on every keystroke.
    public static let primed = ResultSelection(rank: 0)

    /// The rank the highlight has walked to, best-match-first.
    private var rank: Int

    private init(rank: Int) {
        self.rank = rank
    }

    /// The selection after `key` is pressed against a list of `resultCount` rows.
    ///
    /// ↑ walks **up the screen**, toward the weaker matches (rank 1, 2, …); ↓ walks
    /// back down toward the best match. Both **stop at the end of the list rather
    /// than wrapping**, the same way a ⌘-digit past the last Favorite resolves to
    /// nothing rather than coming round again (CONTEXT.md → Key command): a
    /// highlight that reappears at the far end of the list reads as a glitch, not
    /// as navigation. With no results there is nothing to move through and the
    /// selection is unchanged.
    public func moved(_ key: ArrowKey, resultCount: Int) -> ResultSelection {
        guard let from = highlightedRank(in: resultCount) else { return self }
        switch key {
        case .up: return ResultSelection(rank: min(from + 1, resultCount - 1))
        case .down: return ResultSelection(rank: max(from - 1, 0))
        }
    }

    /// Which rank the highlight lands on in a list of `resultCount` rows, or `nil`
    /// when there are none — the [[Home]] case, where there is no highlighted
    /// result and Enter does nothing.
    ///
    /// Results can thin out with no keystroke behind it (an index finishing, a
    /// provider going dark), so a walked highlight is clamped to the weakest row
    /// that still exists rather than pointing past the end of the list.
    public func highlightedRank(in resultCount: Int) -> Int? {
        guard resultCount > 0 else { return nil }
        return min(max(rank, 0), resultCount - 1)
    }

    /// The highlighted row of `rows` — what Return runs, and what the list draws
    /// with the highlight's emphasis and its `⏎` hint. `nil` on an empty list.
    public func highlightedRow(in rows: [ResultRow]) -> ResultRow? {
        guard let rank = highlightedRank(in: rows.count) else { return nil }
        return rows[rank]
    }

    /// Whether the launcher **claims** ↑/↓ from the system right now.
    ///
    /// Like `esc` (CONTEXT.md → Key command) these are unmodified keys, so the
    /// question is not what they do but whether we take them at all — unclaimed,
    /// they keep their own meaning, which for a focused text field is moving the
    /// caret between the lines of a wrapped query. So the launcher takes them only
    /// where they would actually navigate:
    ///
    /// - **There is somewhere to move.** One row, or none, means every press would
    ///   be a no-op that swallowed a working caret key. [[Home]] falls out of this:
    ///   no results, no claim.
    /// - **No [[Quick capture]] is in flight.** A capture owns the bottom bar and
    ///   its own choice list, and Enter there commits the step's best option — the
    ///   Result list is not on screen to walk (issue #267 leaves the capture's own
    ///   keyboard loop alone).
    ///
    /// The App adds the one condition it alone can answer — that the launcher is
    /// the frontmost surface — exactly as it does for `esc`.
    public static func claimsArrowKeys(resultCount: Int, isCapturing: Bool) -> Bool {
        !isCapturing && resultCount > 1
    }
}
