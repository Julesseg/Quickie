import Foundation
import Testing
@testable import QuickieCore

// The single bottom search input grows and wraps as the typed text outgrows one
// line (issue #63): it stays a one-line Capsule, then — past the first line —
// its glass surface squares off into a RoundedRectangle whose ends stay as round
// as the capsule's, growing upward until it caps and scrolls internally.
// `InputBarGrowth` is the pure, platform-agnostic decision; the App feeds it the
// measured content height and maps its result to a SwiftUI shape at the edge.
struct InputBarGrowthTests {

    @Test("the expanded box keeps the one-line capsule's rounded ends")
    func cornerRadiusMatchesCapsuleEnds() {
        // A capsule of a fixed height has ends of radius height/2; the multi-line
        // box reuses exactly that radius so its corners read as the same family.
        let growth = InputBarGrowth(barHeight: 52)
        #expect(growth.cornerRadius == 26)
    }

    @Test("one line of text stays a capsule")
    func oneLineIsNotExpanded() {
        // A single line of content is no taller than one line-height, so the
        // surface stays the one-line Capsule.
        let growth = InputBarGrowth(barHeight: 52)
        #expect(growth.isExpanded(contentHeight: 25, lineHeight: 25, wasExpanded: false) == false)
    }

    @Test("wrapping to a second line expands the surface into the box")
    func secondLineExpands() {
        // Two lines of content stand at roughly twice the line-height — well past
        // the threshold — so the surface squares off into the RoundedRectangle.
        let growth = InputBarGrowth(barHeight: 52)
        #expect(growth.isExpanded(contentHeight: 50, lineHeight: 25, wasExpanded: false) == true)
    }

    @Test("growth caps at five lines before the field scrolls internally")
    func growthCapsAtFiveLines() {
        // Past this many visible lines the field scrolls its content rather than
        // growing further up the screen (the `lineLimit(1...maxLines)` ceiling).
        #expect(InputBarGrowth.maxLines == 5)
    }

    @Test("an already-expanded box holds its shape through wrap-boundary jitter")
    func expandedBoxHoldsThroughJitter() {
        // The bug (issue #80): a `TextField(axis: .vertical)` reports transient,
        // jittery content heights while its text reflows under rapid backspace. A
        // single threshold lets a height hovering right at the wrap boundary flip
        // the glass surface Capsule↔box on every measurement — a burst of
        // Liquid-Glass morphs that stalls the main runloop ("Unable to monitor
        // event loop"). Hysteresis: once expanded, the box stays expanded through
        // that near-boundary band instead of flip-flopping. The *same* measured
        // height that would not expand a collapsed capsule keeps an expanded box
        // expanded.
        let growth = InputBarGrowth(barHeight: 52)
        let lineHeight: CGFloat = 25
        // A height in the dead band just under the one-and-a-half-line expand
        // threshold: it would not expand a fresh capsule…
        #expect(growth.isExpanded(contentHeight: 35, lineHeight: lineHeight, wasExpanded: false) == false)
        // …yet it must not collapse a box that is already expanded — otherwise the
        // shape thrashes as the measurement wobbles across the line.
        #expect(growth.isExpanded(contentHeight: 35, lineHeight: lineHeight, wasExpanded: true) == true)
    }

    @Test("the box collapses only once the text clearly returns to one line")
    func boxCollapsesWhenClearlyOneLine() {
        // Hysteresis is a dead band, not a latch: when the content is unambiguously
        // back to a single line, an expanded box does square back down to the
        // capsule — the shape still tracks reality, it just refuses to flip on
        // boundary noise.
        let growth = InputBarGrowth(barHeight: 52)
        #expect(growth.isExpanded(contentHeight: 25, lineHeight: 25, wasExpanded: true) == false)
    }
}
