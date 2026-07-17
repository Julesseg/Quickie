import Foundation

/// One of the few moments Quickie deliberately animates (ADR 0010): a result row
/// slot appearing or disappearing as the result count changes, and the input
/// gaining focus. Re-ranking is deliberately *not* a moment — result rows are
/// keyed by rank, so a keystroke swaps each slot's content in place rather than
/// moving rows around the screen.
public enum MotionMoment: Sendable {
    case rowInsert
    case inputFocus
    /// Entering or leaving a multi-step capture (issue #37): the browse list
    /// slides out toward the keyboard while the breadcrumb slides in from the top
    /// — a deliberate, whole-screen change rather than a keystroke-adjacent nudge.
    case captureTransition
    /// The Home [[Hint line]] crossfading to its next hint (ADR 0034) — the only
    /// moment with nothing the user just did behind it. Every other moment
    /// *answers* an input; this one starts on its own while the screen sits idle,
    /// which is why it dissolves slowly instead of springing, and why Reduce
    /// Motion stops it outright rather than shortening it (see `hintDwell`).
    case hintRotation
    /// The [[Living backdrop]] mesh drifting between poses on Home (ADR 0034):
    /// alive at rest, calm in use. Unlike every other moment it is not a one-shot
    /// answer to an input — it is a slow, continuous loop, so it carries a
    /// `.drift(period:)` rather than a spring or a fade. The App freezes it the
    /// instant a query exists (results are read over a still backdrop, preserving
    /// ADR 0010's type→choose→run protection), and renders it static under Reduce
    /// Motion — where this degrades to a plain `.fade`, i.e. no drift — as well as
    /// Low Power Mode and UI test, both decided at the App edge.
    case backdropDrift
}

/// How a `MotionMoment` should move: a subtle, fast spring, or a plain crossfade.
/// SwiftUI types never reach Core, so this is mapped to a concrete `Animation`
/// at the App edge.
public enum MotionStyle: Equatable, Sendable {
    /// A subtle, fast spring kept within the animation budget.
    case spring(response: Double, dampingFraction: Double)
    /// A plain crossfade — the Reduce Motion degradation.
    case fade(duration: Double)
    /// A slow, continuous drift that loops rather than settling: the [[Living
    /// backdrop]] mesh easing between poses (ADR 0034). `period` is the seconds
    /// for one leg of the drift (the App loops it with an autoreverse). Distinct
    /// from the one-shot spring/fade because it never lands — a query freezes it,
    /// it does not finish. A *still* backdrop is expressed by degrading this to a
    /// non-`.drift` style (Reduce Motion returns `.fade`).
    case drift(period: Double)
}

/// The tight animation budget from ADR 0010 as a pure, testable decision: subtle
/// springs on the moments that move, degrading to fades when Reduce Motion is on.
public struct MotionPolicy: Sendable {
    public let reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public func style(for moment: MotionMoment) -> MotionStyle {
        if reduceMotion {
            return .fade(duration: 0.15)
        }
        switch moment {
        case .rowInsert:
            return .spring(response: 0.3, dampingFraction: 0.85)
        case .inputFocus:
            // The moment closest to a keystroke — kept the snappiest so the field
            // never feels like it lags the typing.
            return .spring(response: 0.2, dampingFraction: 0.9)
        case .captureTransition:
            // A whole-screen change, so the most deliberate of the budget — still
            // fast, and barely overshooting so a large surface settles cleanly.
            return .spring(response: 0.35, dampingFraction: 0.9)
        case .hintRotation:
            // The one moment outside the spring budget, because it is the one
            // moment the user did not ask for: a slow dissolve the eye can ignore.
            // A spring here would flick a word at someone who is mid-thought —
            // and any motion sharp enough to notice is a motion asking to be read.
            return .fade(duration: 0.8)
        case .backdropDrift:
            // 25s, the middle of ADR 0034's 20–30s band: slow enough that a
            // seconds-long launcher session never sees a full cycle, so the
            // backdrop reads as *living* rather than as something that moves. Far
            // outside the spring budget on purpose — this is the one moment the
            // user never triggers, so it must be impossible to catch in the act.
            return .drift(period: 25)
        }
    }

    /// How long a hint dwells before the [[Hint line]] crossfades to the next, or
    /// `nil` when the line is **frozen** — a single hint, forever.
    ///
    /// Seven seconds is chosen against the wrong instinct: this is the one thing
    /// on screen with nothing to answer to, so the cadence is set to lose an
    /// attention contest with the input rather than win one. Long enough that the
    /// line is furniture to anyone who is typing; short enough that a user who
    /// glances up twice while thinking sees two different capabilities, which is
    /// the entire point of the line (ADR 0034).
    ///
    /// Reduce Motion returns `nil` rather than a longer dwell or a faster fade:
    /// unlike every other moment, there is no user action underneath this one to
    /// preserve, so degrading it still leaves unrequested movement on screen. The
    /// only honest degradation is to stop. The App renders `HintLine()`'s first
    /// hint statically and never advances it — one hint still teaches something;
    /// motion nobody asked for teaches nothing.
    public var hintDwell: Double? {
        reduceMotion ? nil : 7
    }
}
