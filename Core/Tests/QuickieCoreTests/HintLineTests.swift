import Foundation
import Testing
@testable import QuickieCore

// The Home Hint line (ADR 0034): the five quiet, instructive examples that teach
// Quickie's breadth by suggestion rather than by a first-run wall (ADR 0012).
// The copy and the cycling live here so "one capability per hint" is an asserted
// invariant rather than a convention the next edit can quietly break; the App
// only crossfades between whatever `current` says.
struct HintLineTests {

    @Test("the line offers five hints")
    func lineOffersFiveHints() {
        #expect(HintLine.hints.count == 5)
    }

    @Test("every hint is distinct — five phrasings of one trick would teach nothing")
    func hintsAreDistinct() {
        #expect(Set(HintLine.hints).count == HintLine.hints.count)
    }

    @Test("every hint is a real suggestion, not an empty slot")
    func hintsAreNonEmpty() {
        for hint in HintLine.hints {
            #expect(!hint.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("a fresh line starts on the first hint")
    func freshLineStartsOnTheFirstHint() {
        // The frozen rendering (Reduce Motion, UI test) shows exactly this hint
        // and never advances, so the first hint has to stand alone.
        #expect(HintLine().current == HintLine.hints[0])
    }

    @Test("advancing walks every hint in order")
    func advancingWalksEveryHintInOrder() {
        var line = HintLine()
        var seen = [line.current]
        for _ in 1..<HintLine.hints.count {
            line.advance()
            seen.append(line.current)
        }
        #expect(seen == HintLine.hints)
    }

    @Test("the line cycles — it never runs out of hints")
    func lineCyclesRatherThanEnding() {
        // Home can sit open indefinitely, so the last hint wraps to the first
        // rather than sticking or falling off the end.
        var line = HintLine()
        for _ in 0..<HintLine.hints.count {
            line.advance()
        }
        #expect(line.current == HintLine.hints[0])
    }

    @Test("cycling stays in range across many rotations")
    func cyclingStaysInRangeAcrossManyRotations() {
        var line = HintLine()
        for _ in 0..<(HintLine.hints.count * 10 + 3) {
            line.advance()
            #expect(HintLine.hints.contains(line.current))
        }
    }
}
