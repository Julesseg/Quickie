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
        // A broad query surfaces several command rows, so the list is tall enough
        // to scroll and the swipe registers as a real scroll-dismiss.
        input.typeText("s")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing surfaces the Settings command row")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "typing brings the keyboard up"
        )

        // Swipe down on the scrolling result list — the native interactive
        // scroll-dismiss carries the keyboard off-screen with the drag.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)

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
