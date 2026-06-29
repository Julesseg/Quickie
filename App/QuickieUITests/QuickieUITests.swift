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

    /// Returning from a pushed management page lands back on a *focused* input
    /// (ADR 0012, zero-wall — extended to the return trip): after popping the
    /// Settings page, the keyboard comes back up and text typed *without tapping*
    /// goes straight into the field. Proves focus is restored on return, so the
    /// user can keep typing without re-tapping. We drive Settings because its
    /// command row is always present (Quickie ships no default Quicklinks).
    @MainActor
    func testInputRefocusesWhenReturningFromAPage() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        input.typeText("settings")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'settings' surfaces the Settings command")
        row.tap()

        // The Settings page pushes in over the launcher; pop it via the
        // navigation bar's back button.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed Settings page shows a back button")
        back.tap()

        // Back on the launcher: the refocus brings the keyboard up again — the
        // strongest non-flaky proxy for "input focused" — and typing without a
        // tap then filters, the proof the field reclaimed focus on return.
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the launcher input returns after popping the page")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "returning from a page should refocus the input and bring the keyboard back up"
        )
        app.typeText("settings")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
            "with focus restored, typing without tapping should filter results"
        )
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

        // Clear the query so Home returns with the pinned Favorite card. Right
        // after the context menu dismisses, the input's focus and the keyboard can
        // both lag under CI load: a single blind round of deletes can land on a
        // not-yet-focused field (or before the keyboard is up) and clear nothing,
        // leaving the query intact and Home away — the historical flake, asserted
        // on one best-effort attempt. Instead re-focus and re-clear in a loop,
        // polling for the pinned card and stopping the instant Home returns. Each
        // round waits for the keyboard before typing so the deletes can't be
        // swallowed, then deletes a generous *fixed* count: the cursor sits at the
        // end of the short query (so backspaces consume it) and over-deleting an
        // already-empty field is a harmless no-op, so a count comfortably above any
        // test query is the robust choice — more reliable than counting
        // `input.value`, which can momentarily report empty under load.
        let favoriteCard = app.buttons["favorite.builtin.settings"]
        for _ in 0..<5 where !favoriteCard.exists {
            input.tap()
            guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else { continue }
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
            _ = favoriteCard.waitForExistence(timeout: 3)
        }

        // If the card still isn't there, capture *why* in one shot rather than
        // re-running blind: which of the three failure modes are we in? The
        // booleans localize it precisely — query never cleared (the result row
        // lingers), the pin never persisted (Home fell back to its empty
        // placeholder), or the grid rendered but the card's identifier is wrong
        // (the "Favorites" header is up yet the card is absent).
        if !favoriteCard.exists {
            let resultRowLingers = app.buttons["builtin.settings"].exists
            let emptyPlaceholderShown = app.staticTexts["home-placeholder"].exists
            let favoritesHeaderShown = app.staticTexts["Favorites"].exists
            XCTFail("""
            Pinned Favorite card 'favorite.builtin.settings' never appeared on Home. \
            Diagnostics — 'settings' result row still present (query never cleared, Home never returned): \(resultRowLingers); \
            Home empty placeholder shown (pin did not persist — no Favorites, no Recent): \(emptyPlaceholderShown); \
            'Favorites' grid header shown (grid rendered but card identifier mismatched): \(favoritesHeaderShown).
            """)
        }
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
