import XCTest

/// The pre-anything Home's brand mark and [[Hint line]] (ADR 0034) — the parts
/// that can only be verified by driving the real app: that the mark's symbolset
/// actually reaches the *app* target (it lived in the widget extension until
/// #182, and a symbol the app can't resolve fails silently, drawing nothing),
/// that the Hint line is its own element beside the untouched placeholder, and
/// that the rotation is frozen under test.
///
/// The line's *timing* is not tested here and shouldn't be: it lives in
/// `MotionPolicy` and is covered by `MotionPolicyTests`. A UI test can only
/// verify the freeze, which is the part the App edge decides.
final class HomeBrandUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// The mark draws on empty Home. Matched by identifier rather than element
    /// type so the assertion survives SwiftUI classifying a custom symbol
    /// differently than expected — what matters is that it is *there*.
    @MainActor
    func testHomeShowsTheBrandMark() throws {
        let app = launchApp()

        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "the pre-anything Home should be showing"
        )
        let mark = app.descendants(matching: .any)["home-brand-mark"]
        XCTAssertTrue(
            mark.waitForExistence(timeout: 5),
            "the brand mark should render above the placeholder — if this fails, check that "
            + "QuickieEntry/Brand.xcassets reaches the app target, not just QuickieWidgets"
        )
    }

    /// The Hint line is a *separate* element from the placeholder: the
    /// placeholder is the instruction and never changes, the hint is the
    /// suggestion and rotates. Both are on screen at once.
    @MainActor
    func testHintLineIsItsOwnElementBesideTheUnchangedPlaceholder() throws {
        let app = launchApp()

        let placeholder = app.staticTexts["home-placeholder"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
        XCTAssertEqual(placeholder.label, "Start typing", "the placeholder's copy is unchanged by #182")

        let hint = app.staticTexts["home-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "the Hint line should show under the placeholder")
        XCTAssertNotEqual(hint.label, placeholder.label, "the hint is a suggestion, not a second placeholder")
    }

    /// Under UI test the line is frozen to a single static hint — Core's first —
    /// so every other suite's wait on `home-placeholder` isn't racing a screen
    /// that rewrites itself, and so the rotation can't churn SwiftUI's view cache
    /// at automation speed (the crash class issue #79 traced).
    @MainActor
    func testHintLineIsFrozenUnderUITest() throws {
        let app = launchApp()

        let hint = app.staticTexts["home-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertEqual(hint.label, "Try 2+2", "a frozen line shows HintLine's first hint")

        // Comfortably past the rotation's dwell: if the freeze had not taken, the
        // line would have advanced at least once by now.
        Thread.sleep(forTimeInterval: 9)
        XCTAssertEqual(hint.label, "Try 2+2", "the frozen line must never advance under test")
    }
}
