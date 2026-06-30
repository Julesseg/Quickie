import Foundation
import Testing
@testable import QuickieCore

// The tight animation budget from ADR 0010 made into a pure, testable decision:
// subtle, fast springs on the few moments that move — a result row
// inserting/reordering and the input gaining focus — degrading to plain fades
// whenever Reduce Motion is on. `MotionPolicy` is the platform-agnostic policy;
// the App feeds it `accessibilityReduceMotion` and maps each `MotionStyle` to a
// concrete SwiftUI `Animation` at the edge.
struct MotionPolicyTests {

    @Test("a result-row insert animates with a spring when motion is allowed")
    func rowInsertSpringsWhenMotionAllowed() {
        let policy = MotionPolicy(reduceMotion: false)
        guard case .spring = policy.style(for: .rowInsert) else {
            Issue.record("expected a spring, got \(policy.style(for: .rowInsert))")
            return
        }
    }

    @Test("Reduce Motion degrades a row insert to a fade")
    func rowInsertFadesUnderReduceMotion() {
        let policy = MotionPolicy(reduceMotion: true)
        guard case .fade = policy.style(for: .rowInsert) else {
            Issue.record("expected a fade, got \(policy.style(for: .rowInsert))")
            return
        }
    }

    @Test("input focus is snappier than a row settling into place")
    func focusIsSnappierThanRowMotion() {
        // Focus is the moment closest to a keystroke; it must feel instant, so it
        // gets a shorter spring response than a row reordering above it.
        let policy = MotionPolicy(reduceMotion: false)
        guard case .spring(let focus, _) = policy.style(for: .inputFocus),
              case .spring(let row, _) = policy.style(for: .rowInsert) else {
            Issue.record("expected springs when motion is allowed")
            return
        }
        #expect(focus < row)
    }

    @Test("a capture transition is at least as deliberate as a row settling")
    func captureTransitionIsAtLeastAsDeliberateAsARow() {
        // Entering/leaving a capture moves the whole screen, so it reads as a more
        // deliberate gesture than a single row sliding into the ranking — but it
        // stays inside the same tight budget (asserted by `springsStayWithinBudget`).
        let policy = MotionPolicy(reduceMotion: false)
        guard case .spring(let capture, _) = policy.style(for: .captureTransition),
              case .spring(let row, _) = policy.style(for: .rowInsert) else {
            Issue.record("expected springs when motion is allowed")
            return
        }
        #expect(capture >= row)
    }

    @Test("every animated moment degrades to a fade under Reduce Motion",
          arguments: [MotionMoment.rowInsert, .rowReorder, .inputFocus, .captureTransition])
    func allMomentsFadeUnderReduceMotion(_ moment: MotionMoment) {
        let policy = MotionPolicy(reduceMotion: true)
        guard case .fade = policy.style(for: moment) else {
            Issue.record("expected a fade for \(moment), got \(policy.style(for: moment))")
            return
        }
    }

    @Test("springs stay within the tight budget — fast and barely bouncing",
          arguments: [MotionMoment.rowInsert, .rowReorder, .inputFocus, .captureTransition])
    func springsStayWithinBudget(_ moment: MotionMoment) {
        // ADR 0010's "tight animation budget": subtle and fast. A long response or
        // an under-damped, bouncy spring would read as sluggish next to the typing.
        guard case .spring(let response, let damping) = MotionPolicy(reduceMotion: false).style(for: moment) else {
            Issue.record("expected a spring for \(moment)")
            return
        }
        #expect(response <= 0.35)
        #expect(damping >= 0.8 && damping <= 1.0)
    }

    @Test("the Reduce Motion fade is brief, not a slow dissolve")
    func reduceMotionFadeIsBrief() {
        guard case .fade(let duration) = MotionPolicy(reduceMotion: true).style(for: .rowInsert) else {
            Issue.record("expected a fade")
            return
        }
        #expect(duration <= 0.2)
    }
}
