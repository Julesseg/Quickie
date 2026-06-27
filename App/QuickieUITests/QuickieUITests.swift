import XCTest

/// The UI-only acceptance criteria for the walking skeleton (issue #3) that can
/// only be verified by driving the real app on a simulator: auto-focus on
/// launch, the Home placeholder, type→filter, and tap→run. These run on the
/// macOS CI job (XCUITest needs an iOS runtime, which exists only on Apple
/// platforms); the loop's *logic* is covered separately by QuickieCore's tests.
final class QuickieUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// The input auto-focuses on launch, so text typed *without tapping* lands
    /// in it — and the matching built-in Action appears. A strong, non-flaky
    /// proxy for "keyboard up, input focused" (ADR 0012).
    @MainActor
    func testInputAutoFocusesOnLaunch() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")

        // No tap: if auto-focus worked, this text goes straight into the field.
        app.typeText("git")
        XCTAssertTrue(
            app.buttons["builtin.github"].waitForExistence(timeout: 5),
            "typing without tapping should filter results, proving the input auto-focused"
        )
    }

    /// An empty query shows the minimal Home placeholder.
    @MainActor
    func testEmptyQueryShowsHome() throws {
        let app = launchApp()

        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "Home placeholder should show for an empty query"
        )
    }

    /// Typing filters and ranks, and the top row is an interactive control whose
    /// tap runs its main action. We assert the row is hittable and the tap path
    /// is wired without crashing the app — we do *not* assert that Safari opens
    /// (OS behavior, flaky in CI). The open-URL outcome of the main action is
    /// covered deterministically by QuickieCore's SearchEngine tests.
    @MainActor
    func testTypingFiltersAndTapRunsMainAction() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("git")

        let row = app.buttons["builtin.github"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'git' surfaces Open GitHub")
        XCTAssertTrue(row.isHittable, "the result row is an interactive, tappable control")

        row.tap()
        XCTAssertNotEqual(app.state, .notRunning, "running a main action should not crash the app")
    }
}
