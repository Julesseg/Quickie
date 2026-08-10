import Foundation
import Testing
@testable import QuickieCore

// The Shelf as a *launcher surface* (CONTEXT.md → Shelf; ADR 0037; issue #242) — the
// two rules the glass button row above the input is built on, both pure:
//
//  • **When it shows, and what a button commits.** The Shelf means "ways to use *this*
//    query", so it is hidden on an empty one — and it is hidden on exactly the queries
//    a fallback tap could not seed, because both read the same `seed(from:)`.
//  • **How wide a button is.** The row scrolls with no member cap, and the cue that
//    says so is the next button *peeking* past the trailing edge — a sizing decision,
//    so it is derived here rather than eyeballed in the view.
//
// Membership itself (which ids are shelved, in what order) is `FallbackTiers`' job and
// is pinned in `FallbackTiersTests`.
struct FallbackShelfTests {

    // MARK: - Visibility and the committed seed

    @Test("a typed query is the seed a Shelf button commits, verbatim")
    func seedIsTheTypedQuery() {
        #expect(FallbackShelf.seed(from: "dentist") == "dentist")
    }

    @Test("the seed keeps the query's own spacing — the user typed it, we don't tidy it")
    func seedIsNotTrimmed() {
        // Trimming decides *whether* there is a seed, never what it is: a capture's
        // title step receives exactly what was typed, spaces and all.
        #expect(FallbackShelf.seed(from: " buy milk ") == " buy milk ")
    }

    @Test("an empty or whitespace-only query has no seed")
    func blankQueryHasNoSeed() {
        #expect(FallbackShelf.seed(from: "") == nil)
        #expect(FallbackShelf.seed(from: "   ") == nil)
        #expect(FallbackShelf.seed(from: "\n \t") == nil)
    }

    @Test("the Shelf shows exactly when there is a seed to commit")
    func visibilityFollowsTheSeed() {
        // One rule, so the row can never render a button whose tap would open an
        // empty breadcrumb instead of seeding-and-committing.
        #expect(FallbackShelf.isVisible(for: "dentist"))
        #expect(FallbackShelf.isVisible(for: " x "))
        #expect(!FallbackShelf.isVisible(for: ""))
        #expect(!FallbackShelf.isVisible(for: "  "))
    }

    // MARK: - Button sizing

    /// The launcher's real metrics: a button the height of the input bar, the same
    /// 8pt the bottom bar's glass surfaces sit apart, and a 12pt content inset.
    private let layout = FallbackShelf.Layout(
        preferredDiameter: 52, minimumDiameter: 44, spacing: 8, contentInset: 12, peek: 0.5
    )
    /// A 375pt-wide phone (iPhone SE / mini), the narrowest device CI runs.
    private let narrowPhone: CGFloat = 375

    @Test("a row that fits renders at the preferred diameter — nothing to signal")
    func fittingRowUsesThePreferredDiameter() {
        // 12 + 4×52 + 3×8 = 244pt of 375: room to spare, so no shrink and no peek.
        #expect(layout.diameter(availableWidth: narrowPhone, memberCount: 4) == 52)
    }

    @Test("the last row that fits exactly still renders at the preferred diameter")
    func exactlyFittingRowUsesThePreferredDiameter() {
        // 12 + 6×52 + 5×8 = 364 ≤ 375 — the sixth button's trailing edge lands inside
        // the row, so every member is whole and the row does not scroll.
        #expect(layout.diameter(availableWidth: narrowPhone, memberCount: 6) == 52)
    }

    @Test("an overflowing row shrinks so a whole number of buttons plus a peek spans it")
    func overflowingRowSizesForThePeek() {
        // Seven members overflow at 52pt (12 + 7×52 + 6×8 = 424). The row keeps six
        // whole buttons and gives the seventh a half-button peek: the width is
        // 12 + 6d + 6×8 + 0.5d, so d = (375 − 12 − 48) / 6.5.
        let diameter = layout.diameter(availableWidth: narrowPhone, memberCount: 7)
        #expect(abs(diameter - 315 / 6.5) < 0.001)
        #expect(diameter < 52)
    }

    @Test("the peeking button really is cut by the trailing edge")
    func theNextButtonPeeks() {
        // The property the sizing exists for, asserted as the user sees it: the
        // button after the last whole one starts inside the row and ends past it.
        let diameter = layout.diameter(availableWidth: narrowPhone, memberCount: 7)
        let whole = Int((narrowPhone - 12) / (diameter + 8))
        let nextLeadingEdge = 12 + CGFloat(whole) * (diameter + 8)
        #expect(whole < 7, "at least one member is left to peek")
        #expect(nextLeadingEdge < narrowPhone, "the next button starts before the edge")
        #expect(nextLeadingEdge + diameter > narrowPhone, "…and is cut by it")
    }

    @Test("past the peek the row is member-count-independent — the extras just scroll")
    func extraMembersDoNotShrinkTheRowFurther() {
        // There is no member cap, and a longer Shelf must not make every button
        // smaller: seven members and twenty both show the same six-and-a-half.
        let seven = layout.diameter(availableWidth: narrowPhone, memberCount: 7)
        #expect(layout.diameter(availableWidth: narrowPhone, memberCount: 20) == seven)
    }

    @Test("a button never shrinks below the minimum tap target")
    func diameterClampsAtTheMinimum() {
        // A 120pt row would size to ~37pt for a two-and-a-half-button peek; the clamp
        // holds the HIG tap target instead and lets the row simply scroll further —
        // the peek survives as ordinary clipping.
        #expect(layout.diameter(availableWidth: 120, memberCount: 5) == 44)
    }

    @Test("a row that only just overflows shrinks to fit rather than to peek")
    func nearlyFittingRowShrinksToFitEveryMember() {
        // At 360pt six 52s overflow by 4pt, but a six-plus-peek layout would need
        // *bigger* buttons (58.7pt) — there is no peek to be had. Shrink just enough
        // that all six are whole: (360 − 12 − 5×8) / 6.
        let diameter = layout.diameter(availableWidth: 360, memberCount: 6)
        #expect(abs(diameter - 308 / 6) < 0.001)
        #expect(12 + 6 * diameter + 5 * 8 <= 360)
    }

    @Test("an unmeasured row and an empty one fall back to the preferred diameter")
    func degenerateInputsUseThePreferredDiameter() {
        // The first frame, before the row has been measured: no width to divide by.
        #expect(layout.diameter(availableWidth: 0, memberCount: 4) == 52)
        #expect(layout.diameter(availableWidth: narrowPhone, memberCount: 0) == 52)
    }
}
