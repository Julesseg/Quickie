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
        // Start from a clean signals slate so persisted Favorites/Frecency from a
        // prior run can't pollute these tests (issue #9).
        app.launchArguments += ["-uitest-reset-signals"]
        app.launch()
        return app
    }

    /// The input auto-focuses on launch, so text typed *without tapping* lands
    /// in it — and the matching built-in command row appears. Quickie ships no
    /// default Quicklinks (ADR 0013), so we match the always-present "Settings"
    /// command row. A strong, non-flaky proxy for "keyboard up, input focused"
    /// (ADR 0012).
    @MainActor
    func testInputAutoFocusesOnLaunch() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")

        // No tap: if auto-focus worked, this text goes straight into the field.
        app.typeText("settings")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
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
        input.typeText("settings")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'settings' surfaces the Settings command")
        XCTAssertTrue(row.isHittable, "the result row is an interactive, tappable control")

        row.tap()
        XCTAssertNotEqual(app.state, .notRunning, "running a main action should not crash the app")
    }

    /// Pinning an Action as a Favorite via its long-press menu makes it appear in
    /// the Home Favorites grid once the query clears — covering pin (AC #1) and
    /// Home being restored when the input empties. Pinning, unlike tapping,
    /// doesn't run the Action, so the test stays in-app (no hand-off to race). We
    /// pin the always-present "Settings" command row (Quickie ships no default
    /// Quicklinks — ADR 0013).
    @MainActor
    func testPinningAnActionSurfacesItOnHome() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("settings")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'settings' surfaces the Settings command")

        // Long-press opens the Pin/Unpin context menu, then pin it.
        row.press(forDuration: 1.2)
        let pin = app.buttons["Pin as Favorite"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "long-press should offer Pin as Favorite")
        pin.tap()

        // The context menu dismisses itself after a tap, but under CI load the
        // dismissal animation and its dimming platter can linger — and tapping the
        // input while the platter is still up lands on the platter, so the field
        // never refocuses and the deletes type into nothing (Home never returns).
        // Gate on the input being genuinely *hittable* again (platter gone), which
        // is the actual precondition for the next step — a far more robust signal
        // than waiting for a specific menu element to disappear within a tight
        // window. If a stuck platter outlives the first wait, tap the dimmed
        // backdrop (which only dismisses the menu, never activates a row) and wait
        // again, so a slow dismissal can't flake the test.
        if !input.waitForHittable(timeout: 10) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
        XCTAssertTrue(input.waitForHittable(timeout: 10),
                      "the input should be tappable once the Pin menu dismisses")

        // Clear the query — Home returns, now with the pinned Favorite card.
        // Delete a generous *fixed* number of characters rather than counting
        // `input.value`: under CI load the field's value can momentarily report
        // empty, and a count-based clear then under-deletes and leaves the query
        // intact (Home never returns). Over-deleting an already-empty field is a
        // harmless no-op, so a fixed count comfortably above any test query is the
        // robust choice.
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))

        XCTAssertTrue(
            app.buttons["favorite.builtin.settings"].waitForExistence(timeout: 10),
            "the pinned Action should appear as a Favorite card on Home"
        )
    }
}

extension XCUIElement {
    /// Waits until the element is **hittable**, not merely present. An element can
    /// exist while still obscured — e.g. by a context menu's dimming platter as it
    /// animates away — and tapping it then computes an invalid hit point and fails
    /// to focus it. Polling `isHittable` rides out that transient.
    @discardableResult
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
