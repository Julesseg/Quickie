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
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Clean signals slate so persisted Favorites/Frecency can't change which
        // rows appear (mirrors the other UI suites). `extraArguments` lets a test
        // add hooks such as `-uitest-seed-frecent <id>`.
        app.launchArguments += ["-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
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
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "typing brings the keyboard up"
        )

        // Drag down into the keyboard region, starting *on a result row* so the
        // gesture is owned by the result list's scroll view — that is the view
        // carrying `.scrollDismissesKeyboard(.interactively)`. (Targeting
        // `scrollViews.firstMatch` matched an unrelated tiny scroll view at the
        // keyboard's edge, so the list's pan never engaged.) Interactive dismiss
        // follows the finger over the keyboard and carries it off-screen; a quick
        // flick that never reaches the keyboard won't commit, so this is a firm,
        // continuous press-drag to the bottom of the screen (past the input bar,
        // over the keyboard), held briefly so the dismissal sticks.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .default,
            thenHoldForDuration: 0.4
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

    /// The same swipe-down dismissal on Home's **Recent** (Frecency) list — the
    /// other scrolling list that adopted `.scrollDismissesKeyboard(.interactively)`
    /// (issue #71 closes the coverage gap left by #64). The Recent list only
    /// renders with frecency history, so the test seeds two entries through the
    /// real `SignalsStore.record` path via the `-uitest-seed-frecent` launch
    /// argument — no tapping rows to build history first. Two entries make the
    /// list a little taller and let the preserved-rows assertion cover more than
    /// a single row.
    @MainActor
    func testSwipeDownOnRecentListDismissesKeyboardAndPreservesRows() throws {
        let app = launchApp(extraArguments: [
            "-uitest-seed-frecent", "builtin.settings",
            "-uitest-seed-frecent", "builtin.pile-page",
        ])

        // Launch opens straight to Home (empty query, ADR 0012) with the seeded
        // Recent rows — identified by their Action ids, as in the Result list.
        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "seeding frecency renders the Recent list")
        let otherRow = app.buttons["builtin.pile-page"]
        XCTAssertTrue(otherRow.exists, "every seeded entry appears as a Recent row")

        // Bring the keyboard up over Home. Tapping the field (rather than relying
        // on launch auto-focus alone) makes the precondition explicit.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "tapping the input brings the keyboard up over Home"
        )

        // Same firm, continuous press-drag as the Result-list test: start on a
        // Recent row so the gesture is owned by the Recent list's scroll view —
        // the view carrying `.scrollDismissesKeyboard(.interactively)` — and
        // carry the keyboard off-screen, holding briefly so the dismissal sticks.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .default,
            thenHoldForDuration: 0.4
        )

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "swiping down on the Recent list dismisses the keyboard"
        )

        // The bar drops and nothing clears: the Recent rows stay put.
        XCTAssertTrue(row.exists, "the Recent rows are preserved after dismissing the keyboard")
        XCTAssertTrue(otherRow.exists, "every seeded Recent row survives the dismissal")
    }
}
