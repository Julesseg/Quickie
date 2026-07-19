import Foundation
import Testing
@testable import QuickieCore

// The haptic feedback budget from ADR 0034 made into a pure, testable decision —
// the tactile twin of `MotionPolicy`. Only a closed set of moments buzz: a light
// impact on running any action, a firmer impact on pinning/unpinning, a selection
// tick on sealing a breadcrumb step, and a success/error notification when a
// capture lands. `FeedbackPolicy` is the platform-agnostic budget; the App maps
// each `FeedbackStyle` to a concrete UIKit generator at the edge and is its only
// call site, so the enumeration stays the single source of truth.
struct FeedbackPolicyTests {

    @Test("running any action buzzes a light impact")
    func runActionIsLightImpact() {
        #expect(FeedbackPolicy().style(for: .runAction) == .impact(.light))
    }

    @Test("pinning or unpinning is an impact")
    func pinToggleIsAnImpact() {
        guard case .impact = FeedbackPolicy().style(for: .pinToggle) else {
            Issue.record("expected an impact, got \(FeedbackPolicy().style(for: .pinToggle))")
            return
        }
    }

    @Test("a pin lands firmer than the everyday run tap")
    func pinIsFirmerThanARun() {
        // The run beat fires on every tap and Enter, so it is the lightest; a pin is
        // a rarer, more deliberate commitment and reads as the weightier gesture.
        let policy = FeedbackPolicy()
        guard case .impact(let pin) = policy.style(for: .pinToggle),
              case .impact(let run) = policy.style(for: .runAction) else {
            Issue.record("expected impacts for both the pin and the run")
            return
        }
        #expect(pin > run)
    }

    @Test("committing a breadcrumb step is a selection tick")
    func breadcrumbStepIsSelection() {
        // Mid-task progress, not a completion — the lightest tick, so sealing pill
        // after pill never escalates to a run's impact or a capture's notification.
        #expect(FeedbackPolicy().style(for: .breadcrumbStep) == .selection)
    }

    @Test("a capture landing is a success notification, a failure an error")
    func captureConfirmationIsANotification() {
        let policy = FeedbackPolicy()
        #expect(policy.style(for: .captureSucceeded) == .notification(.success))
        #expect(policy.style(for: .captureFailed) == .notification(.error))
    }

    @Test("the structured notification is reserved for a capture finishing",
          // Only the two capture outcomes announce themselves with a notification;
          // the everyday run/pin/step beats stay impacts and ticks so the heavier
          // success/error pattern always means "a task finished with an outcome".
          arguments: [FeedbackMoment.runAction, .pinToggle, .breadcrumbStep])
    func everydayMomentsAreNotNotifications(_ moment: FeedbackMoment) {
        if case .notification = FeedbackPolicy().style(for: moment) {
            Issue.record("expected \(moment) to stay an impact or a tick, got a notification")
        }
    }
}
