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

    /// Returning from a full-screen page (here the "All Notes" library) re-arms
    /// the input's focus, so text typed *without tapping* once back lands in the
    /// field. Presenting a page drops the keyboard and the system doesn't restore
    /// first-responder on return — this proves the app does (ADR 0012, the zero-tap
    /// promise must survive leaving and coming back).
    @MainActor
    func testInputRefocusesAfterReturningFromPage() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("all notes")

        let allNotes = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "All Notes")
        ).firstMatch
        XCTAssertTrue(allNotes.waitForExistence(timeout: 5), "the All Notes command should surface as a result row")
        allNotes.tap()

        // The library page is up; dismiss it back to the input.
        XCTAssertTrue(app.buttons["note-add"].waitForExistence(timeout: 10),
                      "selecting All Notes should open the Note library list page")
        app.buttons["Done"].tap()

        // Back at the input. No tap: if focus was re-armed, this text goes straight
        // into the field — a strong, non-flaky proxy for "keyboard up, input focused".
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        app.typeText(" sentinel")
        XCTAssertTrue(
            ((input.value as? String) ?? "").contains("sentinel"),
            "typing after returning from a page should land in the re-focused input"
        )
    }

    /// Pinning an Action as a Favorite via its long-press menu makes it appear as
    /// a Home shortcut once the query clears — covering pin (AC #1) and Home being
    /// restored when the input empties (AC #5). Pinning, unlike tapping, doesn't
    /// run the Action, so the test stays in-app (no Safari hand-off to race).
    @MainActor
    func testPinningAnActionSurfacesItOnHome() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("git")

        let row = app.buttons["builtin.github"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'git' surfaces Open GitHub")

        // Long-press opens the Pin/Unpin context menu, then pin it.
        row.press(forDuration: 1.2)
        let pin = app.buttons["Pin as Favorite"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "long-press should offer Pin as Favorite")
        pin.tap()

        // Wait for the context menu to fully dismiss before touching the input
        // again. Tapping mid-dismissal lands on the still-present menu platter
        // dimming the input: the tap computes an invalid hit point, the field
        // never regains focus, and the subsequent deletes type into nothing —
        // leaving the query uncleared so Home never returns.
        XCTAssertTrue(pin.waitForNonExistence(timeout: 5), "the Pin menu should dismiss after pinning")
        XCTAssertTrue(input.waitForHittable(timeout: 5), "the input should be tappable once the menu dismisses")

        // Clear the query — Home returns, now with the pinned Favorite shortcut.
        // Delete the field's current contents rather than a hard-coded count so
        // the clear doesn't silently under-delete if the query ever changes.
        input.tap()
        let typed = (input.value as? String) ?? ""
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))

        XCTAssertTrue(
            app.buttons["favorite.builtin.github"].waitForExistence(timeout: 5),
            "the pinned Action should appear as a Favorite shortcut on Home"
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
