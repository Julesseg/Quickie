import Foundation
import Testing
@testable import QuickieCore

// What a tap on a breadcrumb crumb does (CONTEXT.md → Pointer hover; issue #263).
// Two kinds of crumb are controls — a filled pill behind the cursor, and the one
// empty step directly ahead of it — and every other crumb is a read-only label that
// happens to look like the pills beside it. The rule lives here rather than in the
// breadcrumb view because it now answers two questions at once: what a tap *runs*,
// and whether the crumb is a control at all, which is what decides whether a pointer
// hovering it lights up.
struct CrumbTapTests {

    /// A run of crumbs: `values` gives each step's committed value (`nil` = unfilled)
    /// and `cursor` the index the capture sits on, mirroring what `MultiStepAction`
    /// hands the breadcrumb.
    private func steps(_ values: [String?], cursor: Int) -> [BreadcrumbStep] {
        values.enumerated().map { index, value in
            BreadcrumbStep(
                index: index,
                label: "Step \(index)",
                value: value.map { ArgumentValue.text($0) },
                isCurrent: index == cursor
            )
        }
    }

    // MARK: - The controls

    /// A filled pill behind the cursor re-edits: tapping "yesterday" to change it is
    /// the whole reason the crumbs are tappable.
    @Test("a filled pill that isn't the current step re-edits that step")
    func filledPillReEdits() {
        let run = steps(["a", "b", nil], cursor: 2)
        #expect(run.crumbTap(for: run[0]) == .reEdit(index: 0))
        #expect(run.crumbTap(for: run[1]) == .reEdit(index: 1))
    }

    /// The next empty step advances — the same thing Enter does, so tapping ahead
    /// never commits something Enter wouldn't (its own empty-guard still applies).
    @Test("the empty step directly after the cursor advances, exactly like Enter")
    func nextEmptyStepAdvances() {
        let run = steps(["a", nil, nil], cursor: 1)
        #expect(run.crumbTap(for: run[2]) == .advance)
    }

    // MARK: - The labels

    /// The current crumb is where the cursor already is: tapping it has nothing to do.
    @Test("the current step is inert, filled or not")
    func currentStepIsInert() {
        let collecting = steps(["a", nil, nil], cursor: 1)
        #expect(collecting.crumbTap(for: collecting[1]) == .inert)
        // Re-editing puts the cursor back on a *filled* step; it is still the cursor.
        let reEditing = steps(["a", "b", nil], cursor: 0)
        #expect(reEditing.crumbTap(for: reEditing[0]) == .inert)
    }

    /// A step two or more ahead of the cursor is not reachable in one tap — advancing
    /// to it would have to commit the steps in between, which the user hasn't filled.
    @Test("an empty step beyond the next one is inert")
    func stepsFurtherAheadAreInert() {
        let run = steps(["a", nil, nil, nil], cursor: 1)
        #expect(run.crumbTap(for: run[3]) == .inert)
    }

    /// A finished run — the cursor past the last step — has no current crumb at all.
    /// Every filled pill still re-edits, and there is no empty step to advance to.
    @Test("with no cursor on any step, filled pills still re-edit and nothing advances")
    func noCursorLeavesOnlyReEdits() {
        let run = steps(["a", "b"], cursor: 99)
        #expect(run.crumbTap(for: run[0]) == .reEdit(index: 0))
        #expect(run.crumbTap(for: run[1]) == .reEdit(index: 1))
    }

    // MARK: - A whole run at once

    /// The shape the breadcrumb view reads: every crumb of one run, verdict by verdict.
    /// This is what decides which crumbs are buttons — and so which ones light up under
    /// a pointer — so it is asserted as a whole rather than a case at a time.
    @Test("a run resolves to its two acting crumbs and its labels")
    func aWholeRunResolves() {
        let run = steps(["a", "b", nil, nil], cursor: 2)
        #expect(run.map { run.crumbTap(for: $0) } == [
            .reEdit(index: 0),   // filled, behind the cursor
            .reEdit(index: 1),   // filled, behind the cursor
            .inert,              // the cursor itself
            .advance,            // the one empty step ahead
        ])
    }
}
