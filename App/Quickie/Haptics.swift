import UIKit
import QuickieCore

/// Maps QuickieCore's platform-agnostic feedback decision onto concrete UIKit
/// haptic generators at the App edge — the tactile twin of `Motion.swift`. The
/// *budget* — which moments buzz and how firm each is — lives in `FeedbackPolicy`
/// and is unit tested there (ADR 0034); this file only fires the matching
/// generator. It is the **single** haptic call site in the app, so the enumerated
/// budget stays the one source of truth: a new buzz means a new `FeedbackMoment`,
/// never a stray generator dropped inline (issue #180).
@MainActor
enum Haptics {
    private static let policy = FeedbackPolicy()

    /// Play the haptic the budget declares for `moment`. On the simulator the
    /// generators are silent no-ops, so nothing special guards UI test — there is
    /// no feedback to churn the suite, only the same signal a device would feel.
    static func play(_ moment: FeedbackMoment) {
        switch policy.style(for: moment) {
        case .impact(let weight):
            UIImpactFeedbackGenerator(style: weight.uiStyle).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .notification(let notice):
            UINotificationFeedbackGenerator().notificationOccurred(notice.uiType)
        }
    }
}

private extension FeedbackImpactWeight {
    var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        }
    }
}

private extension FeedbackNotice {
    var uiType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success: return .success
        case .error: return .error
        }
    }
}
