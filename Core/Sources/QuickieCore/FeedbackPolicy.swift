import Foundation

/// One of the few moments Quickie deliberately produces a haptic (ADR 0034) — the
/// tactile twin of `MotionPolicy`'s animation budget. Every case answers something
/// the user just did: running an action, pinning a Favorite, sealing a breadcrumb
/// step, or a capture landing. The set is deliberately *closed* — these are the
/// only moments that buzz, so the budget stays the single source of truth.
///
/// One near-moment is pointedly absent: the [[Highlighted result]] changing. It
/// changes on nearly every keystroke, so a tick there would buzz under the typing
/// thumb and fight the keyboard's own haptics (ADR 0034) — the haptic equivalent
/// of `MotionPolicy` deliberately *not* animating a re-rank. There is simply no
/// case for it, which is the enforcement.
public enum FeedbackMoment: Sendable {
    /// Running any action — a result-row tap, a Favorite tap, or Enter on the
    /// Highlighted result (CONTEXT.md → Main action). The core type→choose→run beat.
    case runAction
    /// Pinning or unpinning a Favorite from a row's long-press menu (issue #9).
    case pinToggle
    /// Sealing one step of a multi-step capture breadcrumb (issue #37): a pill
    /// commits and the cursor advances to the next step. Deliberately *not* the
    /// final commit — that step's beat is the capture's success/error confirmation,
    /// so the run doesn't tick and buzz in the same instant.
    case breadcrumbStep
    /// A capture validated and its record landed (issue #37) — the beat paired with
    /// the confirmation toast.
    case captureSucceeded
    /// A capture failed to write (issue #37) — the beat paired with the failure toast.
    case captureFailed
}

/// How a `FeedbackMoment` feels: a physical impact of some weight, a light
/// selection tick, or a success/error notification. UIKit's haptic generators
/// never reach Core, so this is mapped to a concrete generator at the App edge.
public enum FeedbackStyle: Equatable, Sendable {
    /// A physical thud whose firmness scales with `weight` — the everyday beat for
    /// a discrete action completing.
    case impact(FeedbackImpactWeight)
    /// The lightest tick, for moving between the steps of one ongoing task — a
    /// breadcrumb pill sealing, mirroring a picker detent.
    case selection
    /// A structured success/error pattern, reserved for a task *finishing* with an
    /// outcome to announce — a capture writing its record, or failing to.
    case notification(FeedbackNotice)
}

/// The firmness of an impact haptic — only the two rungs the budget actually
/// emits, kept closed like `MotionStyle` rather than mirroring every UIKit weight.
/// `Comparable` so the budget's relative choices are assertable: a pin lands firmer
/// than a row tap without pinning either to a literal case in the tests.
public enum FeedbackImpactWeight: Int, Sendable, Comparable {
    case light
    case medium

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The two structured notifications the budget uses — the tail end of a capture.
public enum FeedbackNotice: Equatable, Sendable {
    case success
    case error
}

/// The haptic feedback budget from ADR 0034 as a pure, testable decision — the
/// tactile twin of `MotionPolicy`. It enumerates the only moments that buzz and
/// how firm each one is; the App feeds a `FeedbackMoment` in and fires the matching
/// UIKit generator at the edge, so this policy is the single source of truth for
/// the budget.
public struct FeedbackPolicy: Sendable {
    public init() {}

    public func style(for moment: FeedbackMoment) -> FeedbackStyle {
        switch moment {
        case .runAction:
            // The most frequent beat — every tap and Enter — so it is the lightest
            // impact: present enough to confirm the run, never a thud that tires.
            return .impact(.light)
        case .pinToggle:
            // A deliberate, less frequent commitment (a menu choice to keep an
            // Action), so it lands firmer than the everyday run tap to read as the
            // weightier gesture it is.
            return .impact(.medium)
        case .breadcrumbStep:
            // Mid-task progress, not a completion: the lightest selection tick, the
            // same detent a picker gives as it moves between values.
            return .selection
        case .captureSucceeded:
            return .notification(.success)
        case .captureFailed:
            return .notification(.error)
        }
    }
}
