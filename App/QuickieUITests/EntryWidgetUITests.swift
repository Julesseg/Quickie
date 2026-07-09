import XCTest

/// The UI-only acceptance for the deep-link widget's **warm-resume reset** (issue
/// #124): tapping the widget opens `quickie://entry`, which must clear a stale
/// query and abandon a half-filled breadcrumb, landing on a clean, focused Home —
/// exactly like a cold launch (ADR 0012), while an app-icon/switcher resume keeps
/// state. The `quickie://entry` parse grammar is Core-covered
/// (`QuickieDeeplinkTests`); this proves the app-side `handleDeeplink(.entry)` →
/// reset + refocus wiring the widget's `widgetURL` reaches through the root
/// `onOpenURL`.
///
/// XCUITest can neither deliver a `quickie://` URL nor tap a Home-Screen widget, so
/// the reset is driven through the *real* dispatch path via the `-uitest-entry`
/// launch argument, which arms a hidden `uitest-entry-trigger` — the same "drive
/// the real path" seam the deeplink and Favorites-pin suites use. The Reminder
/// breadcrumb rides `-uitest-stub-reminders` because the simulator's Reminders
/// permission dialog can't be pre-granted.
final class EntryWidgetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-entry",
        ] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// A warm entry reset clears a stale query and lands on a focused Home. Type a
    /// query (no capture), fire the entry reset, and the field empties back to the
    /// Home placeholder with the keyboard still up — typing without a tap filters
    /// again, the strongest non-flaky proxy for "input refocused" (ADR 0012).
    @MainActor
    func testEntryResetClearsStaleQuery() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        input.typeText("settings")

        // The query surfaced a real row — proof there is a stale query to clear.
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
            "typing 'settings' surfaces a result, so there is a stale query to clear"
        )

        // Fire the entry reset through the real `handleDeeplink(.entry)` path.
        let trigger = app.buttons["uitest-entry-trigger"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "the -uitest-entry seam should arm its trigger")
        trigger.tap()

        // The reset empties the query back to Home: the stale row is gone and the
        // empty-query Home placeholder returns.
        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "the entry reset should clear the stale query back to a clean Home"
        )
        XCTAssertFalse(
            app.buttons["builtin.settings"].exists,
            "the stale result row should be gone after the reset"
        )

        // Home is *focused*: the keyboard stays up and typing without a tap filters
        // again — the proof the reset re-armed focus rather than just clearing.
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "the entry reset should land on a focused Home with the keyboard up"
        )
        app.typeText("settings")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
            "with focus restored, typing without tapping should filter again"
        )
    }

    /// A warm entry reset abandons a half-filled breadcrumb. Start the New Reminder
    /// capture (breadcrumb at the title step), fire the entry reset, and the
    /// breadcrumb's `capture-input` is gone — the launcher is back on its plain
    /// `search-input`, focused — proving `resetToLauncher` cancelled the in-flight
    /// capture rather than leaving it stranded on top.
    @MainActor
    func testEntryResetAbandonsInFlightBreadcrumb() throws {
        let app = launchApp(extraArguments: ["-uitest-stub-reminders"])

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        input.typeText("reminder")

        let row = app.buttons["builtin.new-reminder"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing surfaces the New Reminder row")
        row.tap()

        // The breadcrumb is now in-flight on the title step — a half-filled capture.
        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(captureField.waitForExistence(timeout: 10), "the New Reminder breadcrumb starts on the title step")

        // Fire the entry reset: it must abandon the capture back to the launcher.
        let trigger = app.buttons["uitest-entry-trigger"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "the -uitest-entry seam should arm its trigger")
        trigger.tap()

        // The breadcrumb field is gone and the plain search input is back, focused —
        // a clean, focused Home, the capture abandoned rather than left in flight.
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the launcher's plain input returns after the reset")
        XCTAssertFalse(
            app.textFields["capture-input"].exists,
            "the in-flight capture breadcrumb should be abandoned by the reset"
        )
        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "abandoning the breadcrumb should land on a clean Home"
        )
    }
}
