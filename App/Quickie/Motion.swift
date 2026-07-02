import SwiftUI
import QuickieCore

/// Maps QuickieCore's platform-agnostic motion decision onto the concrete
/// SwiftUI types at the App edge. The *policy* — what moves, how fast, and when
/// it degrades to a fade for Reduce Motion — lives in `MotionPolicy` and is unit
/// tested there (ADR 0010); this file only translates each `MotionStyle` into an
/// `Animation` and pairs it with the matching transition.
extension MotionStyle {
    /// Under UI test, collapse motion to instant (issue #79). The result list's
    /// animated row insert/remove transitions — move+opacity inside a
    /// `GlassEffectContainer` — driven at automation speed churn SwiftUI's
    /// DisplayList view cache fast enough to trip an internal assertion
    /// (`DisplayList.ViewUpdater.ViewCache.update` → `_assertionFailure`,
    /// `EXC_BREAKPOINT`), which flaked the XCUITest suite. Removing the
    /// transitions at the SwiftUI layer stops the churn without the crash that
    /// globally disabling UIKit animations (`setAnimationsEnabled(false)`) caused
    /// — that broke the very `performWithoutAnimation:` commit path this render
    /// depends on. Read once; normal launches never pass the flag.
    static let isInstantForUITesting =
        ProcessInfo.processInfo.arguments.contains("-uitest-instant-motion")

    /// The concrete animation curve for this motion decision, or `nil` under UI
    /// test so the change applies with no animation.
    var animation: Animation? {
        if Self.isInstantForUITesting { return nil }
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
    /// Under UI test it is `.identity`: the view swaps in place with no transition,
    /// so nothing is mid-flight to churn the DisplayList cache.
    func edgeTransition(from edge: Edge) -> AnyTransition {
        if Self.isInstantForUITesting { return .identity }
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
