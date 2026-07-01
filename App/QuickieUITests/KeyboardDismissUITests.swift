import XCTest

/// The swipe-down keyboard dismissal (issue #64): swiping down on a scrolling
/// list interactively dismisses the keyboard the native iOS way
/// (`.scrollDismissesKeyboard(.interactively)`), the input bar drops to the
/// bottom without clearing the query or results, and tapping the field brings the
/// keyboard back. Only verifiable by driving the real app on a simulator, so it
/// runs on the macOS XCUITest CI job.
final class KeyboardDismissUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Clean signals slate so persisted Favorites/Frecency can't change which
        // rows appear (mirrors the other UI suites).
        app.launchArguments += ["-uitest-reset-signals"]
        app.launch()
        return app
    }

    /// Swiping down on the Result list interactively dismisses the keyboard, and
    /// nothing clears: the query text and the surfaced results are preserved, so
    /// dismissing just gets the keyboard out of the way. Tapping the input field
    /// re-summons the keyboard — the only re-summon path.
    @MainActor
    func testSwipeDownOnResultListDismissesKeyboardAndPreservesQuery() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        // A broad query surfaces many command rows (every built-in containing
        // "s", plus the web-search fallback), so the list is tall enough to scroll
        // and the drag registers as a real scroll-dismiss.
        input.typeText("s")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing surfaces the Settings command row")
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the result list is a scroll view")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "typing brings the keyboard up"
        )

        // Drag down the list into the keyboard region. Interactive scroll-dismiss
        // follows the finger over the keyboard's frame and carries it off-screen —
        // a quick flick within the upper list never reaches the keyboard, so this
        // is a firm, continuous press-drag from inside the list to the bottom of
        // the screen (past the input bar, over the keyboard), held briefly so the
        // dismissal commits rather than snapping back.
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(
            forDuration: 0.2,
            thenDragTo: end,
            withVelocity: .default,
            thenHoldForDuration: 0.3
        )

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "swiping down on the result list dismisses the keyboard"
        )

        // Bar drops, nothing clears: the query text and the results are unchanged.
        XCTAssertEqual(
            input.value as? String, "s",
            "dismissing the keyboard leaves the query text unchanged"
        )
        XCTAssertTrue(row.exists, "the results are preserved after dismissing the keyboard")

        // Tapping the input field re-summons the keyboard.
        input.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "tapping the input field re-summons the keyboard"
        )
    }
}
