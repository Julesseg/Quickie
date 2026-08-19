import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import QuickieCore

/// The bottom bar's keyboard lift as a pure decision (issue #58 × #64, extended
/// to windowed geometry by issue #261): the bar must track the keyboard
/// *exactly* — riding its own show animation and following the finger during an
/// interactive swipe-dismiss — while still holding its inset when a context menu
/// transiently drops the keyboard, and it must do so in every iPad window
/// configuration and with every keyboard style.
///
/// Every rect below is in the **window's** coordinate space: the App converts
/// the notification's screen-space end-frame with `UIWindow.convert(_:from:)`
/// before handing it over, so a windowed app sees the keyboard where it actually
/// falls across *its* bottom edge rather than the screen's.
final class KeyboardBarLiftTests: XCTestCase {

    // MARK: - Window fixtures

    /// An 11" iPad at full screen: the window is the whole display.
    private static let fullScreen = CGRect(x: 0, y: 0, width: 834, height: 1194)

    /// The same iPad in half-width Split View. In the window's own coordinates
    /// the origin is still zero — only the width shrinks — which is exactly the
    /// trap the old screen-space math fell into.
    private static let splitView = CGRect(x: 0, y: 0, width: 507, height: 1194)

    /// A Stage Manager window floating clear of the display bottom: its last
    /// 100pt sit over the keyboard, the rest above it.
    private static let stageManager = CGRect(x: 0, y: 0, width: 700, height: 800)

    /// A docked keyboard `height` tall, spanning `window` and running off its
    /// bottom edge. `overhang` widens it past both sides, as a screen-wide
    /// keyboard does once converted into a narrower window's coordinates.
    private static func docked(
        height: CGFloat,
        over window: CGRect,
        overhang: CGFloat = 0,
        belowWindowBottom: CGFloat = 0
    ) -> CGRect {
        CGRect(
            x: window.minX - overhang,
            y: window.maxY - height + belowWindowBottom,
            width: window.width + overhang * 2,
            height: height
        )
    }

    /// A keyboard that has left the window entirely: the end-frame of a
    /// dismissal, parked just under the window's bottom edge.
    private static func dismissed(height: CGFloat, under window: CGRect) -> CGRect {
        docked(height: height, over: window, belowWindowBottom: height)
    }

    // MARK: - The full-screen baseline

    /// A real software keyboard rising lifts the bar to the keyboard's top —
    /// animated in step with the keyboard itself, and measured above the bottom
    /// safe area the bar already sits in.
    func testKeyboardShowingLiftsBarAnimatedWithKeyboard() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.docked(height: 364, over: Self.fullScreen),
            windowBounds: Self.fullScreen,
            bottomSafeArea: 20,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 344))
    }

    /// A dismissal that commits while the list is being dragged is the
    /// intentional swipe-dismiss (issue #64): the bar drops with the keyboard.
    func testDismissalWhileScrollingDropsBarWithKeyboard() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.dismissed(height: 364, under: Self.fullScreen),
            windowBounds: Self.fullScreen,
            bottomSafeArea: 20,
            isListScrolling: true,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    /// A dismissal while the list is still and a software keyboard was up is the
    /// context menu resigning first responder (issue #58): hold the inset so the
    /// long-press never reflows the list.
    func testDismissalWhileStillHoldsInset() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.dismissed(height: 364, under: Self.fullScreen),
            windowBounds: Self.fullScreen,
            bottomSafeArea: 20,
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
            keyboardFrame: Self.dismissed(height: 364, under: Self.fullScreen),
            windowBounds: Self.fullScreen,
            bottomSafeArea: 20,
            isListScrolling: false,
            usesKeyboardlessControl: true
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    // MARK: - Windowed configurations (issue #261)

    /// Half-width Split View: the screen-wide keyboard overhangs both sides of
    /// the window once converted, and still covers its full bottom band. The
    /// lift is the keyboard's height, not some fraction of a screen the window
    /// no longer fills.
    func testSplitViewWindowLiftsByTheFullKeyboardHeight() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.docked(height: 364, over: Self.splitView, overhang: 260),
            windowBounds: Self.splitView,
            bottomSafeArea: 20,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 344))
    }

    /// A resized Stage Manager window sits clear of the display bottom, so the
    /// keyboard covers only its last 100pt and runs on past it. The bar lifts by
    /// what is actually covered — and the keyboard is still classified by its
    /// **own** height, so this clipped 100pt overlap is not mistaken for a
    /// hardware keyboard's accessory bar.
    func testStageManagerWindowLiftsByTheCoveredBandOnly() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.docked(
                height: 364,
                over: Self.stageManager,
                overhang: 60,
                belowWindowBottom: 264
            ),
            windowBounds: Self.stageManager,
            bottomSafeArea: 0,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 100))
    }

    /// A Stage Manager window floating entirely above the keyboard is not
    /// covered at all: coverage is zero, so nothing lifts it. This is the case
    /// the old screen-space math got worst — it read the keyboard's distance
    /// from the *display* bottom and lifted the bar a full keyboard's height
    /// over a window the keyboard never touched.
    func testWindowClearOfTheKeyboardIsNotCovered() {
        XCTAssertEqual(
            KeyboardBarLift.coverage(
                keyboardFrame: Self.dismissed(height: 364, under: Self.stageManager),
                windowBounds: Self.stageManager
            ),
            .docked(overlap: 0)
        )
    }

    // MARK: - Undocked keyboards (issue #261)

    /// A floating keyboard is a small detached slab: it never reaches the
    /// window's bottom edge, so it covers no band the bar must clear. The bar
    /// **rests at the window bottom** — released, not held, so undocking a
    /// keyboard that had lifted the bar drops it back down.
    func testFloatingKeyboardProducesNoLift() {
        let floating = CGRect(x: 380, y: 700, width: 320, height: 260)
        let change = KeyboardBarLift.notified(
            keyboardFrame: floating,
            windowBounds: Self.fullScreen,
            bottomSafeArea: 20,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    /// A split keyboard reports a window-wide frame, but a raised one: its two
    /// halves are lifted off the bottom edge. Detached is detached — zero lift.
    func testSplitKeyboardProducesNoLift() {
        let split = CGRect(x: 0, y: 620, width: 834, height: 300)
        let change = KeyboardBarLift.notified(
            keyboardFrame: split,
            windowBounds: Self.fullScreen,
            bottomSafeArea: 20,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    // MARK: - Hardware keyboards

    /// A hardware keyboard's thin shortcuts bar is docked like any keyboard, so
    /// the bar rides on top of it — lifted by the accessory bar's own coverage,
    /// never by a stale full-keyboard inset left over from before the hardware
    /// keyboard attached.
    func testAccessoryBarLiftsByTheAccessoryBarOnly() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.docked(height: 55, over: Self.fullScreen),
            windowBounds: Self.fullScreen,
            bottomSafeArea: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 21))
    }

    /// An accessory bar leaving is not the context-menu case: with a hardware
    /// keyboard attached there is no software keyboard whose inset could be
    /// worth preserving, so the bar drops rather than freezing above a dead band.
    func testAccessoryBarLeavingReleasesRatherThanHolds() {
        let change = KeyboardBarLift.notified(
            keyboardFrame: Self.dismissed(height: 55, under: Self.fullScreen),
            windowBounds: Self.fullScreen,
            bottomSafeArea: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    /// The software-keyboard classification reads the keyboard's **own** height,
    /// so it is independent of how much of it any given window happens to see.
    func testSoftwareKeyboardClassificationIsIndependentOfTheWindow() {
        XCTAssertTrue(KeyboardBarLift.isSoftwareKeyboard(height: 364))
        XCTAssertFalse(KeyboardBarLift.isSoftwareKeyboard(height: 55))
        XCTAssertFalse(
            KeyboardBarLift.isSoftwareKeyboard(height: KeyboardBarLift.softwareKeyboardThreshold)
        )
    }

    // MARK: - Coverage classification

    /// The three ways a keyboard end-frame can relate to a window, named once so
    /// the lift rules above read as policy rather than geometry.
    func testCoverageClassifiesDockedUndockedAndAway() {
        XCTAssertEqual(
            KeyboardBarLift.coverage(
                keyboardFrame: Self.docked(height: 364, over: Self.splitView, overhang: 260),
                windowBounds: Self.splitView
            ),
            .docked(overlap: 364)
        )
        XCTAssertEqual(
            KeyboardBarLift.coverage(
                keyboardFrame: CGRect(x: 380, y: 700, width: 320, height: 260),
                windowBounds: Self.fullScreen
            ),
            .undocked
        )
        XCTAssertEqual(
            KeyboardBarLift.coverage(
                keyboardFrame: Self.dismissed(height: 364, under: Self.fullScreen),
                windowBounds: Self.fullScreen
            ),
            .docked(overlap: 0)
        )
        XCTAssertEqual(
            KeyboardBarLift.coverage(keyboardFrame: .zero, windowBounds: Self.fullScreen),
            .away
        )
    }

    // MARK: - The live drag channel

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
