import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import QuickieCore

/// The bottom bar's keyboard lift as a pure decision (issue #58 × #64, extended
/// to windowed geometry by issue #261): the bar must track the keyboard
/// *exactly* — riding its own show animation and following the finger during an
/// interactive swipe-dismiss — while still holding its inset when a context menu
/// transiently drops the keyboard, in every iPad window configuration and with
/// every keyboard style.
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

    /// A Slide Over panel: narrow *and* floating clear of the display's bottom
    /// edge, so it is neither of the two cases above.
    private static let slideOver = CGRect(x: 0, y: 0, width: 320, height: 1000)

    /// A Stage Manager window floating clear of the display bottom: its last
    /// 100pt sit over the keyboard, the rest above it.
    private static let stageManager = CGRect(x: 0, y: 0, width: 700, height: 800)

    /// A docked keyboard `height` tall, spanning `window` and running off its
    /// bottom edge. `overhang` widens it past both sides, as a display-wide
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

    private static func geometry(
        _ keyboardFrame: CGRect,
        in window: CGRect,
        bottomSafeArea: CGFloat
    ) -> KeyboardBarLift.Geometry {
        KeyboardBarLift.Geometry(
            keyboardFrame: keyboardFrame,
            windowBounds: window,
            bottomSafeArea: bottomSafeArea
        )
    }

    /// The ordinary notified decision: a local keyboard, list still, no
    /// keyboard-less control. The cases that vary those say so.
    private static func lift(_ geometry: KeyboardBarLift.Geometry) -> KeyboardBarLift.Change {
        KeyboardBarLift.notified(
            geometry,
            isLocalKeyboard: true,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
    }

    // MARK: - The full-screen baseline

    /// A real software keyboard rising lifts the bar to the keyboard's top —
    /// animated in step with the keyboard itself, and measured above the bottom
    /// safe area the bar already sits in.
    func testKeyboardShowingLiftsBarAnimatedWithKeyboard() {
        XCTAssertEqual(
            Self.lift(Self.geometry(
                Self.docked(height: 364, over: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 20
            )),
            .animateWithKeyboard(inset: 344)
        )
    }

    /// A dismissal that commits while the list is being dragged is the
    /// intentional swipe-dismiss (issue #64): the bar drops with the keyboard.
    func testDismissalWhileScrollingDropsBarWithKeyboard() {
        let change = KeyboardBarLift.notified(
            Self.geometry(
                Self.dismissed(height: 364, under: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 20
            ),
            isLocalKeyboard: true,
            isListScrolling: true,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    /// A dismissal while the list is still and a software keyboard was up is the
    /// context menu resigning first responder (issue #58): hold the inset so the
    /// long-press never reflows the list.
    func testDismissalWhileStillHoldsInset() {
        XCTAssertEqual(
            Self.lift(Self.geometry(
                Self.dismissed(height: 364, under: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 20
            )),
            .hold
        )
    }

    /// A dismissal while a capture shows a keyboard-less control (the date
    /// step's picker, the primer/denial affordances) releases the inset — the
    /// text field was removed for the whole step, so the control takes the
    /// keyboard's space rather than floating above a dead band.
    func testDismissalIntoKeyboardlessControlReleasesInset() {
        let change = KeyboardBarLift.notified(
            Self.geometry(
                Self.dismissed(height: 364, under: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 20
            ),
            isLocalKeyboard: true,
            isListScrolling: false,
            usesKeyboardlessControl: true
        )
        XCTAssertEqual(change, .animateWithKeyboard(inset: 0))
    }

    // MARK: - Windowed configurations (issue #261)

    /// Half-width Split View: the display-wide keyboard overhangs both sides of
    /// the window once converted, and still covers its full bottom band. The
    /// lift is the keyboard's height, not some fraction of a display the window
    /// no longer fills.
    func testSplitViewWindowLiftsByTheFullKeyboardHeight() {
        XCTAssertEqual(
            Self.lift(Self.geometry(
                Self.docked(height: 364, over: Self.splitView, overhang: 260),
                in: Self.splitView,
                bottomSafeArea: 20
            )),
            .animateWithKeyboard(inset: 344)
        )
    }

    /// A Slide Over panel is narrow *and* floats above the display's bottom
    /// edge, so the display-wide keyboard both overhangs it and runs past its
    /// bottom: the bar lifts by the band actually covered, not by the keyboard's
    /// height.
    func testSlideOverPanelLiftsByTheCoveredBandOnly() {
        XCTAssertEqual(
            Self.lift(Self.geometry(
                Self.docked(
                    height: 364,
                    over: Self.slideOver,
                    overhang: 350,
                    belowWindowBottom: 180
                ),
                in: Self.slideOver,
                bottomSafeArea: 0
            )),
            .animateWithKeyboard(inset: 184)
        )
    }

    /// A resized Stage Manager window sits clear of the display bottom, so the
    /// keyboard covers only its last 100pt and runs on past it. The bar lifts by
    /// what is actually covered — and the keyboard is still classified by its
    /// **own** height, so this clipped 100pt overlap is not mistaken for a
    /// hardware keyboard's accessory bar.
    func testStageManagerWindowLiftsByTheCoveredBandOnly() {
        let geometry = Self.geometry(
            Self.docked(
                height: 364,
                over: Self.stageManager,
                overhang: 60,
                belowWindowBottom: 264
            ),
            in: Self.stageManager,
            bottomSafeArea: 0
        )
        XCTAssertTrue(
            geometry.isSoftwareKeyboard,
            "a full keyboard seen through a short window is still a full keyboard — the classification reads its own height, not the clipped overlap"
        )
        XCTAssertEqual(Self.lift(geometry), .animateWithKeyboard(inset: 100))
    }

    /// Under iPadOS 26's free placement a window can hang off a display edge, so
    /// the display-wide keyboard never reaches that edge of it. Docking is
    /// judged on the keyboard being *as wide as* the window, not on covering it
    /// corner to corner, so the visible bottom band still lifts the bar.
    func testWindowHangingOffTheDisplayEdgeStillDocks() {
        // The window's leading 200pt are off the display; the keyboard starts at
        // the display's left edge, 200pt into the window's own coordinates.
        let window = CGRect(x: 0, y: 0, width: 900, height: 1000)
        let keyboard = CGRect(x: 200, y: 636, width: 1024, height: 364)
        XCTAssertEqual(
            KeyboardBarLift.Geometry(
                keyboardFrame: keyboard,
                windowBounds: window,
                bottomSafeArea: 20
            ).coverage,
            .docked(overlap: 364)
        )
    }

    /// A Stage Manager window floating entirely above the keyboard is not
    /// covered at all: coverage is zero, so nothing lifts it. This is the case
    /// the old screen-space math got worst — it read the keyboard's distance
    /// from the *display* bottom and lifted the bar a full keyboard's height
    /// over a window the keyboard never touched.
    func testWindowClearOfTheKeyboardIsNotCovered() {
        XCTAssertEqual(
            Self.geometry(
                Self.dismissed(height: 364, under: Self.stageManager),
                in: Self.stageManager,
                bottomSafeArea: 0
            ).coverage,
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
        XCTAssertEqual(
            Self.lift(Self.geometry(floating, in: Self.fullScreen, bottomSafeArea: 20)),
            .animateWithKeyboard(inset: 0)
        )
    }

    /// A split keyboard reports a window-wide frame, but a raised one: its two
    /// halves are lifted off the bottom edge. Detached is detached — zero lift.
    func testSplitKeyboardProducesNoLift() {
        let split = CGRect(x: 0, y: 620, width: 834, height: 300)
        XCTAssertEqual(
            Self.lift(Self.geometry(split, in: Self.fullScreen, bottomSafeArea: 20)),
            .animateWithKeyboard(inset: 0)
        )
    }

    // MARK: - Hardware keyboards

    /// A hardware keyboard's thin shortcuts bar is docked like any keyboard, so
    /// the bar rides on top of it — lifted by the accessory bar's own coverage,
    /// never by a stale full-keyboard inset left over from before the hardware
    /// keyboard attached.
    func testAccessoryBarLiftsByTheAccessoryBarOnly() {
        XCTAssertEqual(
            Self.lift(Self.geometry(
                Self.docked(height: 55, over: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 34
            )),
            .animateWithKeyboard(inset: 21)
        )
    }

    /// An accessory bar leaving is not the context-menu case: with a hardware
    /// keyboard attached there is no software keyboard whose inset could be
    /// worth preserving, so the bar drops rather than freezing above a dead band.
    func testAccessoryBarLeavingReleasesRatherThanHolds() {
        XCTAssertEqual(
            Self.lift(Self.geometry(
                Self.dismissed(height: 55, under: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 34
            )),
            .animateWithKeyboard(inset: 0)
        )
    }

    /// The software-keyboard classification reads the keyboard's **own** height,
    /// so it is independent of how much of it any given window happens to see.
    func testSoftwareKeyboardClassificationIsIndependentOfTheWindow() {
        XCTAssertFalse(
            Self.geometry(
                Self.docked(height: KeyboardBarLift.softwareKeyboardThreshold, over: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 0
            ).isSoftwareKeyboard,
            "the threshold itself is an accessory bar — the test is strictly greater"
        )
    }

    // MARK: - Somebody else's keyboard

    /// Side by side on iPad, the *other* app's keyboard posts the same
    /// notification. It may well cover our window, but nothing of ours is
    /// focused, so it must leave our bar exactly where it is.
    func testNonLocalKeyboardHoldsTheInset() {
        let change = KeyboardBarLift.notified(
            Self.geometry(
                Self.docked(height: 364, over: Self.splitView, overhang: 260),
                in: Self.splitView,
                bottomSafeArea: 20
            ),
            isLocalKeyboard: false,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        XCTAssertEqual(change, .hold)
    }

    // MARK: - Coverage classification

    /// The three ways a keyboard end-frame can relate to a window, named once so
    /// the lift rules above read as policy rather than geometry.
    func testCoverageClassifiesDockedUndockedAndAway() {
        XCTAssertEqual(
            Self.geometry(
                Self.docked(height: 364, over: Self.splitView, overhang: 260),
                in: Self.splitView,
                bottomSafeArea: 0
            ).coverage,
            .docked(overlap: 364)
        )
        XCTAssertEqual(
            Self.geometry(
                CGRect(x: 380, y: 700, width: 320, height: 260),
                in: Self.fullScreen,
                bottomSafeArea: 0
            ).coverage,
            .undocked
        )
        XCTAssertEqual(
            Self.geometry(
                Self.dismissed(height: 364, under: Self.fullScreen),
                in: Self.fullScreen,
                bottomSafeArea: 0
            ).coverage,
            .docked(overlap: 0)
        )
        XCTAssertEqual(
            Self.geometry(.zero, in: Self.fullScreen, bottomSafeArea: 0).coverage,
            .away
        )
    }

    // MARK: - Capture step changes

    /// Committing a text step into a keyboard-less one (the date picker)
    /// releases the inset at the step change itself — immediately, unanimated —
    /// so the picker lays out in its final position behind the dismissing
    /// keyboard instead of appearing keyboard-high and sliding down with it.
    func testEnteringKeyboardlessStepDropsInsetInstantly() {
        XCTAssertEqual(
            KeyboardBarLift.stepChanged(usesKeyboardlessControl: true),
            .track(inset: 0)
        )
    }

    /// A step change back to a keyboard-full control decides nothing — the
    /// keyboard-show notification owns the lift, riding the keyboard's rise.
    func testEnteringKeyboardFullStepHoldsForTheKeyboardShow() {
        XCTAssertEqual(
            KeyboardBarLift.stepChanged(usesKeyboardlessControl: false),
            .hold
        )
    }

    // MARK: - The live channel

    /// A live sample during a list drag is the finger moving the keyboard (the
    /// interactive swipe-dismiss): the bar tracks it exactly — applied
    /// immediately, unanimated, and clamped at the safe-area floor.
    func testLiveSampleWhileScrollingTracksKeyboardExactly() {
        XCTAssertEqual(
            KeyboardBarLift.live(
                overlap: 210,
                bottomSafeArea: 34,
                isListScrolling: true,
                windowChangedShape: false
            ),
            .track(inset: 176)
        )
        XCTAssertEqual(
            KeyboardBarLift.live(
                overlap: 20,
                bottomSafeArea: 34,
                isListScrolling: true,
                windowChangedShape: false
            ),
            .track(inset: 0)
        )
    }

    /// Dragging a Split View divider or resizing a Stage Manager window changes
    /// how much of a **stationary** keyboard the window sits over, and the
    /// keyboard posts nothing to say so. Without this the bar would keep the
    /// inset it had at the window's old size (issue #261).
    func testWindowReshapeReseatsTheBarWithoutADrag() {
        XCTAssertEqual(
            KeyboardBarLift.live(
                overlap: 120,
                bottomSafeArea: 20,
                isListScrolling: false,
                windowChangedShape: true
            ),
            .track(inset: 100)
        )
    }

    /// Live samples that are neither are the keyboard's own show/hide animation
    /// playing out (or a context-menu resignation) — ignored, so they never
    /// fight the notified channel or a held inset.
    func testLiveSampleWhileStillAndUnreshapedIsIgnored() {
        XCTAssertEqual(
            KeyboardBarLift.live(
                overlap: 210,
                bottomSafeArea: 34,
                isListScrolling: false,
                windowChangedShape: false
            ),
            .hold
        )
    }
}
