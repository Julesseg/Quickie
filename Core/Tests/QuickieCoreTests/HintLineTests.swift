import Foundation
import Testing
@testable import QuickieCore

// The Home Hint line (ADR 0034): the five quiet, instructive examples that teach
// Quickie's breadth by suggestion rather than by a first-run wall (ADR 0012).
// The copy and the cycling live here so "one capability per hint" is an asserted
// invariant rather than a convention the next edit can quietly break; the App
// only crossfades between whatever `current` says.
struct HintLineTests {

    /// A small seedable generator so the *random* rotation can be exercised
    /// deterministically — `SystemRandomNumberGenerator` can't be seeded, and a
    /// flaky shuffle test is worse than none. SplitMix64: standard, well-mixed,
    /// enough for a five-item shuffle.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

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
        // and never advances, so the first hint has to stand alone — and it is the
        // one deliberately chosen opener (arithmetic: "not an app list").
        #expect(HintLine().current == HintLine.hints[0])
    }

    @Test("advancing always lands on a real hint")
    func advancingStaysOnARealHint() {
        var generator = SeededGenerator(seed: 1)
        var line = HintLine()
        for _ in 0..<(HintLine.hints.count * 20 + 3) {
            line.advance(using: &generator)
            #expect(HintLine.hints.contains(line.current))
        }
    }

    @Test("the line never shows the same hint twice in a row")
    func advancingNeverRepeatsBackToBack() {
        // A rotation that dissolved a hint into itself would read as the crossfade
        // stuttering on nothing. The seam between two shuffled passes is the only
        // place it could happen, so walk well past several passes.
        var generator = SeededGenerator(seed: 7)
        var line = HintLine()
        var previous = line.current
        for _ in 0..<(HintLine.hints.count * 20) {
            line.advance(using: &generator)
            #expect(line.current != previous)
            previous = line.current
        }
    }

    @Test("every hint appears exactly once per pass — the whole point is coverage",
          arguments: [UInt64(1), 2, 3, 42, 12345])
    func everyHintAppearsOncePerPass(seed: UInt64) {
        // A shuffle bag, not independent random draws: within any five consecutive
        // rotations the user must see every capability once. Each bag is exactly
        // five advances (the first `advance()` refills, then five pops drain it),
        // so a pass is aligned to the very first advance — no warm-up needed.
        var generator = SeededGenerator(seed: seed)
        var line = HintLine()

        for _ in 0..<10 {
            var seenThisPass: [String] = []
            for _ in 0..<HintLine.hints.count {
                line.advance(using: &generator)
                seenThisPass.append(line.current)
            }
            #expect(Set(seenThisPass) == Set(HintLine.hints),
                    "a pass of five rotations should show all five hints, saw \(seenThisPass)")
        }
    }

    @Test("the order actually varies — it isn't a fixed cycle in disguise")
    func rotationOrderVaries() {
        // The complaint that started this: a line that always ran 0,1,2,3,4 read as
        // canned. Two different seeds should not produce identical sequences.
        func sequence(seed: UInt64) -> [String] {
            var generator = SeededGenerator(seed: seed)
            var line = HintLine()
            return (0..<HintLine.hints.count * 2).map { _ in
                line.advance(using: &generator)
                return line.current
            }
        }
        #expect(sequence(seed: 1) != sequence(seed: 2))
    }
}
