import Foundation
import Testing
@testable import QuickieCore

// The tight animation budget from ADR 0010 made into a pure, testable decision:
// subtle, fast springs on the few moments that move — a result row slot
// appearing/disappearing and the input gaining focus — degrading to plain fades
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
        // gets a shorter spring response than a row slot settling above it.
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
          arguments: [MotionMoment.rowInsert, .inputFocus, .captureTransition, .hintRotation, .backdropDrift])
    func allMomentsFadeUnderReduceMotion(_ moment: MotionMoment) {
        let policy = MotionPolicy(reduceMotion: true)
        guard case .fade = policy.style(for: moment) else {
            Issue.record("expected a fade for \(moment), got \(policy.style(for: moment))")
            return
        }
    }

    @Test("springs stay within the tight budget — fast and barely bouncing",
          // `.hintRotation` and `.backdropDrift` are deliberately absent: they are
          // the moments that crossfade or loop rather than spring even when motion
          // is allowed, so the spring budget has nothing to say about them
          // (`hintRotationDissolves`, `backdropDrifts`).
          arguments: [MotionMoment.rowInsert, .inputFocus, .captureTransition])
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

    // MARK: - The Hint line's rotation (#182)

    @Test("the Hint line dissolves rather than springs, even when motion is allowed")
    func hintRotationDissolves() {
        // Every other moment answers something the user just did, so it springs.
        // The Hint line is the one thing Quickie animates on its own initiative —
        // it must read as ambient, never as a nudge asking to be looked at.
        let policy = MotionPolicy(reduceMotion: false)
        guard case .fade = policy.style(for: .hintRotation) else {
            Issue.record("expected a fade, got \(policy.style(for: .hintRotation))")
            return
        }
    }

    @Test("the Hint crossfade is slow — a dissolve, not a keystroke-speed swap")
    func hintCrossfadeIsSlow() {
        guard case .fade(let hint) = MotionPolicy(reduceMotion: false).style(for: .hintRotation),
              case .fade(let reduceMotion) = MotionPolicy(reduceMotion: true).style(for: .rowInsert) else {
            Issue.record("expected fades")
            return
        }
        // Comfortably slower than the brief Reduce Motion degradation, and slow
        // enough that peripheral vision reads it as a dissolve rather than a cut.
        #expect(hint > reduceMotion)
        #expect(hint >= 0.5)
    }

    @Test("each hint dwells long enough to read and ignore")
    func hintDwellIsUnhurried() {
        guard let dwell = MotionPolicy(reduceMotion: false).hintDwell else {
            Issue.record("expected the line to rotate when motion is allowed")
            return
        }
        // Long enough that the line never competes with the input for attention,
        // short enough that a user who looks up twice sees two different hints.
        #expect(dwell >= 5)
        #expect(dwell <= 10)
    }

    @Test("a hint outlasts its own crossfade")
    func hintOutlastsItsCrossfade() {
        // Otherwise the line would spend its life mid-dissolve and never settle
        // on anything legible.
        let policy = MotionPolicy(reduceMotion: false)
        guard let dwell = policy.hintDwell,
              case .fade(let crossfade) = policy.style(for: .hintRotation) else {
            Issue.record("expected a rotating line with a crossfade")
            return
        }
        #expect(dwell > crossfade * 2)
    }

    @Test("Reduce Motion freezes the line rather than fading it faster")
    func reduceMotionFreezesTheHintLine() {
        // The rotation *is* the motion: there is no gesture underneath it to
        // preserve, so a shorter fade would still be unrequested movement. The
        // line stops instead, and the App renders a single static hint.
        #expect(MotionPolicy(reduceMotion: true).hintDwell == nil)
    }

    // MARK: - The Living backdrop's drift (#184)

    @Test("the backdrop drifts — a continuous loop, not a spring or a fade")
    func backdropDrifts() {
        // The one moment the user never triggers, so it never springs: it eases
        // slowly and forever between poses, which is a `.drift`, not a transition.
        guard case .drift = MotionPolicy(reduceMotion: false).style(for: .backdropDrift) else {
            Issue.record("expected a drift, got \(MotionPolicy(reduceMotion: false).style(for: .backdropDrift))")
            return
        }
    }

    @Test("the drift period sits in ADR 0034's 20–30s band — alive at rest, never caught moving")
    func driftPeriodStaysSlow() {
        // Slow enough that a seconds-long launcher session never sees a full
        // cycle (the whole point — motion the eye can ignore), but not so slow it
        // stops reading as alive. ADR 0034 pins the band to 20–30s.
        guard case .drift(let period) = MotionPolicy(reduceMotion: false).style(for: .backdropDrift) else {
            Issue.record("expected a drift")
            return
        }
        #expect(period >= 20 && period <= 30)
    }

    @Test("Reduce Motion stops the drift outright — a still backdrop, no loop")
    func backdropIsStillUnderReduceMotion() {
        // Degrades to a non-`.drift` style (the shared `.fade` path), so the App's
        // "drift only if the style is `.drift`" rule renders a static mesh — the
        // honest degradation for motion the user never asked for (ADR 0034).
        let style = MotionPolicy(reduceMotion: true).style(for: .backdropDrift)
        if case .drift = style {
            Issue.record("expected Reduce Motion to stop the drift, still got \(style)")
        }
    }
}
