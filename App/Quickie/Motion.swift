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

    /// The transition for a view entering from `edge` (and leaving back toward it)
    /// under this style: a directional slide while fading for a spring, the bare
    /// crossfade for the Reduce Motion degradation — movement dropped entirely.
    func edgeTransition(from edge: Edge) -> AnyTransition {
        switch self {
        case .spring:
            return .move(edge: edge).combined(with: .opacity)
        case .fade:
            return .opacity
        }
    }

    /// The transition that pairs with this style for a result row: it slides in
    /// from the bottom edge (toward the input/thumb) while fading.
    var insertionTransition: AnyTransition { edgeTransition(from: .bottom) }
}
