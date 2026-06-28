import SwiftUI
import QuickieCore

/// Maps QuickieCore's platform-agnostic motion decision onto the concrete
/// SwiftUI types at the App edge. The *policy* — what moves, how fast, and when
/// it degrades to a fade for Reduce Motion — lives in `MotionPolicy` and is unit
/// tested there (ADR 0010); this file only translates each `MotionStyle` into an
/// `Animation` and pairs it with the matching transition.
extension MotionStyle {
    /// The concrete animation curve for this motion decision.
    var animation: Animation {
        switch self {
        case .spring(let response, let dampingFraction):
            return .spring(response: response, dampingFraction: dampingFraction)
        case .fade(let duration):
            // Reduce Motion degradation: a plain crossfade, no movement.
            return .easeInOut(duration: duration)
        }
    }

    /// The transition that pairs with this style. A spring slides a row in from
    /// the bottom edge (toward the input/thumb) while fading; the Reduce Motion
    /// fade drops the movement entirely.
    var insertionTransition: AnyTransition {
        switch self {
        case .spring:
            return .move(edge: .bottom).combined(with: .opacity)
        case .fade:
            return .opacity
        }
    }
}
