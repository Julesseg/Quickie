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
        #expect(growth.isExpanded(contentHeight: 25, lineHeight: 25) == false)
    }

    @Test("wrapping to a second line expands the surface into the box")
    func secondLineExpands() {
        // Two lines of content stand at roughly twice the line-height — well past
        // the threshold — so the surface squares off into the RoundedRectangle.
        let growth = InputBarGrowth(barHeight: 52)
        #expect(growth.isExpanded(contentHeight: 50, lineHeight: 25) == true)
    }

    @Test("growth caps at five lines before the field scrolls internally")
    func growthCapsAtFiveLines() {
        // Past this many visible lines the field scrolls its content rather than
        // growing further up the screen (the `lineLimit(1...maxLines)` ceiling).
        #expect(InputBarGrowth.maxLines == 5)
    }
}
