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
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Start from a clean signals slate so persisted Favorites/Frecency from a
        // prior run can't pollute these tests (issue #9). `extraArguments` lets a
        // test add hooks such as `-uitest-pin-favorite <id>`.
        app.launchArguments += ["-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
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

    /// A pinned Favorite renders as a card in the Home Favorites grid (issue #9
    /// AC #1). The pin is seeded through the real `SignalsStore.toggleFavorite`
    /// path via the `-uitest-pin-favorite` launch argument rather than the
    /// long-press context menu: XCUITest cannot fire a SwiftUI context-menu item's
    /// action in the iOS simulator (the menu is a separate remote view — the tap
    /// is synthesized but the action never runs), though the gesture works on
    /// device. So this covers the persistence + Home-rendering half here, and the
    /// long-press gesture is verified manually on device. We seed the
    /// always-present "Settings" command row (Quickie ships no default Quicklinks
    /// — ADR 0013).
    @MainActor
    func testPinnedFavoriteSurfacesOnHome() throws {
        let app = launchApp(extraArguments: ["-uitest-pin-favorite", "builtin.settings"])

        // Launch opens straight to Home (empty query, ADR 0012). The seeded
        // Favorite should be there as a card — proof the pin persisted and the
        // grid renders it. No typing or gesture, so nothing to race.
        XCTAssertTrue(
            app.buttons["favorite.builtin.settings"].waitForExistence(timeout: 10),
            "a pinned Action should appear as a Favorite card on Home"
        )
    }

    /// A pinned **Fallback** renders as a Favorite card too (CONTEXT.md →
    /// Favorite, Fallback Action): a fallback-flagged Action is part of the
    /// enumerable catalog, so its pin must draw a card rather than silently
    /// consuming a slot — and must survive the launch-time reconciliation that
    /// prunes unresolvable pins. Seeded the same way as the test above, with the
    /// default "Search the web" Custom Action (`seed.web-search`) — a text-first
    /// fallback that *is* standalone-runnable, so it stays pinnable (unlike a
    /// query-only capture such as Save for later, which issue #140 excludes).
    @MainActor
    func testPinnedFallbackSurfacesOnHome() throws {
        let app = launchApp(extraArguments: ["-uitest-pin-favorite", "seed.web-search"])

        // The default seed is now inserted before the first render (QuickieApp.init),
        // so a pinned Favorite pointing at it draws its card on first Home render
        // without racing a mid-launch @Query refresh. Keep modest headroom only for
        // the slow iPhone SE CI runner's launch time, not for a resolution race.
        XCTAssertTrue(
            app.buttons["favorite.seed.web-search"].waitForExistence(timeout: 15),
            "a pinned Fallback should appear as a Favorite card on Home"
        )
    }
}
