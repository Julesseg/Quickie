import Foundation

/// The spring UIKit animates the software keyboard with — a `CASpringAnimation`
/// of these parameters (the animation behind the keyboard notifications'
/// private curve). The bar's `.keyboardSpring` motion maps to exactly this at
/// the App edge, which is what keeps the bar glued to the keyboard instead of
/// trailing it on a generic curve.
public enum KeyboardSpring {
    public static let mass: Double = 3
    public static let stiffness: Double = 1000
    public static let damping: Double = 500
}

/// One resolved movement of the bottom bar's **held** keyboard lift (issues
/// #58 × #64): the inset the bar should sit at, and how to get there. The App
/// drives the lift manually — SwiftUI's automatic keyboard avoidance is off —
/// so following the keyboard *exactly* is this policy's whole job.
public struct KeyboardLift: Equatable, Sendable {
    /// How the bar should move to `inset`.
    public enum Motion: Equatable, Sendable {
        /// Move in lockstep with the keyboard's own animation. UIKit animates
        /// the keyboard with the spring in `KeyboardSpring`; animating the bar
        /// with anything else (the old generic ease-out) leaves it trailing the
        /// keyboard and settling late.
        case keyboardSpring
        /// Apply immediately, with no animation at all: the value is a live
        /// per-frame sample of an interactive drag, so the finger *is* the
        /// animation and any curve would trail it.
        case direct
    }

    public let inset: CGFloat
    public let motion: Motion

    public init(inset: CGFloat, motion: Motion) {
        self.inset = inset
        self.motion = motion
    }
}

/// The pure decision behind the bar's keyboard lift: given a keyboard event and
/// the launcher's context, the new lift — or `nil` to **hold** the current one
/// (the issue-#58 context-menu freeze). Platform-agnostic and unit-tested; the
/// App feeds it keyboard frames and maps `Motion` to a concrete animation.
public struct KeyboardLiftPolicy: Sendable {
    public init() {}

    /// Resolves a keyboard **will-change-frame** event — a scheduled keyboard
    /// animation — to the lift it calls for.
    ///
    /// - Parameters:
    ///   - overlap: How much of the screen the keyboard's end frame covers,
    ///     measured from the screen bottom.
    ///   - currentInset: The lift the bar currently holds.
    ///   - bottomSafeAreaInset: The home-indicator inset the bar already sits
    ///     above; the keyboard's overlap is measured from the screen bottom, so
    ///     lifting by the full overlap would float the bar one inset too high.
    ///   - isListScrolling: Whether a result/Recent list is mid-drag — the
    ///     signal that a dismissal is the intentional swipe (issue #64).
    ///   - usesKeyboardlessControl: Whether the capture in flight replaced the
    ///     text field with a keyboard-less control, so the keyboard is
    ///     structurally gone and the bar should reclaim its space.
    public func lift(
        forOverlap overlap: CGFloat,
        currentInset: CGFloat,
        bottomSafeAreaInset: CGFloat,
        isListScrolling: Bool,
        usesKeyboardlessControl: Bool
    ) -> KeyboardLift? {
        if overlap > Self.liftThreshold {
            return KeyboardLift(
                inset: max(0, overlap - bottomSafeAreaInset),
                motion: .keyboardSpring
            )
        }
        // The keyboard is leaving. Mid-drag it is the intentional swipe
        // (issue #64); during a keyboard-less capture step the text field was
        // removed for the whole step, so the keyboard is structurally gone; and
        // a bar already tracked below the threshold is proof an interactive
        // dismiss is finishing (a hold never lowers it), even if the scroll
        // phase went idle before this settle event fired. Any of these:
        // release, riding the keyboard's own spring down.
        if isListScrolling || usesKeyboardlessControl || currentInset < Self.liftThreshold {
            return KeyboardLift(inset: 0, motion: .keyboardSpring)
        }
        // A dismissal while the list is still is the context menu resigning
        // first responder — hold the lift so the long-press doesn't reflow the
        // list (issue #58).
        return nil
    }

    /// Resolves a live per-frame keyboard **sample** — the keyboard's current
    /// overlap while an interactive swipe-dismiss drags it (issue #64). No
    /// will-change notification fires until that gesture ends, so these samples
    /// are the only signal that can keep the bar glued to the keyboard's top
    /// edge mid-drag. Same parameters as `lift(forOverlap:…)`.
    public func tracking(
        forOverlap overlap: CGFloat,
        currentInset: CGFloat,
        bottomSafeAreaInset: CGFloat,
        isListScrolling: Bool,
        usesKeyboardlessControl: Bool
    ) -> KeyboardLift? {
        // A low sample obeys the same hide rules as a will-change: only an
        // intentional swipe (mid-drag) or a structurally keyboard-less step may
        // move the bar down — a context menu's resign holds (issue #58).
        if overlap <= Self.liftThreshold && !isListScrolling && !usesKeyboardlessControl {
            return nil
        }
        return KeyboardLift(
            inset: max(0, overlap - bottomSafeAreaInset),
            motion: .direct
        )
    }

    /// The smallest overlap that reads as a real software keyboard — a
    /// hardware-keyboard accessory bar sits below this and never lifts the bar.
    public static let liftThreshold: CGFloat = 120
}
