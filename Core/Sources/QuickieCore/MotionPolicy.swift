import Foundation

/// One of the few moments Quickie deliberately animates (ADR 0010): a result row
/// inserting or reordering as the ranking shifts, and the input gaining focus.
public enum MotionMoment: Sendable {
    case rowInsert
    case rowReorder
    case inputFocus
}

/// How a `MotionMoment` should move: a subtle, fast spring, or a plain crossfade.
/// SwiftUI types never reach Core, so this is mapped to a concrete `Animation`
/// at the App edge.
public enum MotionStyle: Equatable, Sendable {
    /// A subtle, fast spring kept within the animation budget.
    case spring(response: Double, dampingFraction: Double)
    /// A plain crossfade — the Reduce Motion degradation.
    case fade(duration: Double)
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
        case .rowInsert, .rowReorder:
            return .spring(response: 0.3, dampingFraction: 0.85)
        case .inputFocus:
            // The moment closest to a keystroke — kept the snappiest so the field
            // never feels like it lags the typing.
            return .spring(response: 0.2, dampingFraction: 0.9)
        }
    }
}
