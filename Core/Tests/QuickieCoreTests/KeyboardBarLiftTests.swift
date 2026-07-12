import XCTest
@testable import QuickieCore

/// The bottom bar's keyboard lift as a pure decision (issue #58 × #64 follow-up):
/// the bar must track the keyboard *exactly* — riding its own show animation and
/// following the finger during an interactive swipe-dismiss — while still holding
/// its inset when a context menu transiently drops the keyboard.
final class KeyboardBarLiftTests: XCTestCase {

    /// A real software keyboard rising (overlap over the accessory-bar threshold)
    /// lifts the bar to the keyboard's top — animated in step with the keyboard
    /// itself, and measured above the bottom safe area the bar already sits in.
    func testKeyboardShowingLiftsBarAnimatedWithKeyboard() {
        let change = KeyboardBarLift.notified(
            overlap: 336,
            bottomSafeArea: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 302))
    }

    /// A dismissal that commits while the list is being dragged is the
    /// intentional swipe-dismiss (issue #64): the bar drops with the keyboard.
    func testDismissalWhileScrollingDropsBarWithKeyboard() {
        let change = KeyboardBarLift.notified(
            overlap: 0,
            bottomSafeArea: 34,
            isListScrolling: true,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    /// A dismissal while the list is still and a keyboard-full control is up is
    /// the context menu resigning first responder (issue #58): hold the inset so
    /// the long-press never reflows the list.
    func testDismissalWhileStillHoldsInset() {
        let change = KeyboardBarLift.notified(
            overlap: 0,
            bottomSafeArea: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .hold)
    }

    /// A dismissal while a capture shows a keyboard-less control (the date
    /// step's picker, the primer/denial affordances) releases the inset — the
    /// text field was removed for the whole step, so the control takes the
    /// keyboard's space rather than floating above a dead band.
    func testDismissalIntoKeyboardlessControlReleasesInset() {
        let change = KeyboardBarLift.notified(
            overlap: 0,
            bottomSafeArea: 34,
            isListScrolling: false,
            usesKeyboardlessControl: true
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    /// A hardware keyboard's thin accessory bar (overlap at or under the
    /// software-keyboard threshold) never lifts the bar — and, while the list is
    /// still, never disturbs a held inset either.
    func testAccessoryBarOverlapHoldsInset() {
        let change = KeyboardBarLift.notified(
            overlap: 55,
            bottomSafeArea: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .hold)
    }

    /// A live keyboard-frame sample during a list drag is the finger moving the
    /// keyboard (the interactive swipe-dismiss): the bar tracks it exactly —
    /// applied immediately, unanimated, and clamped at the safe-area floor.
    func testDragSampleWhileScrollingTracksKeyboardExactly() {
        XCTAssertEqual(
            KeyboardBarLift.dragged(overlap: 210, bottomSafeArea: 34, isListScrolling: true),
            .track(inset: 176)
        )
        XCTAssertEqual(
            KeyboardBarLift.dragged(overlap: 20, bottomSafeArea: 34, isListScrolling: true),
            .track(inset: 0)
        )
    }

    /// Live samples while the list is still are the keyboard's own show/hide
    /// animation playing out (or a context-menu resignation), not a drag —
    /// ignored, so they never fight the notified channel or a held inset.
    func testDragSampleWhileStillIsIgnored() {
        XCTAssertEqual(
            KeyboardBarLift.dragged(overlap: 210, bottomSafeArea: 34, isListScrolling: false),
            .hold
        )
    }
}
