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

    /// Launches the app and dumps its state + accessibility tree to the test
    /// log, so a CI failure shows exactly what rendered instead of just
    /// "element not found".
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        print("== Quickie launch state: \(app.state.rawValue) (3 == runningForeground)")
        print("== Quickie accessibility tree ==\n\(app.debugDescription)")
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

    /// Typing filters and ranks; tapping the row runs its main action (opens a
    /// URL, which deactivates the app as the browser takes over).
    @MainActor
    func testTypingFiltersAndTapRunsMainAction() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("git")

        let row = app.buttons["builtin.github"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'git' surfaces Open GitHub")

        row.tap()
        // Tapping opens the URL; the app resigns active as the browser opens.
        let wentInactive = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue),
            object: app
        )
        XCTAssertEqual(XCTWaiter().wait(for: [wentInactive], timeout: 10), .completed,
                       "running the main action should open the URL and background the app")
    }
}
