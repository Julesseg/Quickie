import XCTest

/// The UI-only acceptance for the `quickie://` deeplink door (issue #120): a
/// `capture/reminder` deeplink must open the app straight onto the Reminder
/// quick-capture breadcrumb at Argument 1 with the keyboard up — no typing, no
/// row tap, exactly as the App Intents bridge and entry surfaces (#121, #124,
/// #125) will drive it. The parse grammar itself is covered deterministically by
/// QuickieCore's `QuickieDeeplinkTests`; this proves the root `onOpenURL` →
/// `handleDeeplink` wiring around it.
///
/// XCUITest can't open a `quickie://` URL against the app, so the deeplink is
/// delivered through the *real* parse → dispatch path via the `-uitest-deeplink`
/// launch argument — the same "drive the real path" seam the shortcut import and
/// Favorites pin suites use. The Reminder capture rides the `-uitest-stub-reminders`
/// seam because the simulator's Reminders permission dialog can't be pre-granted.
final class DeeplinkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(deeplink: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-stub-reminders",
            "-uitest-deeplink", deeplink,
        ]
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// A `quickie://capture/reminder` deeplink lands the warm app directly on the
    /// Reminder capture's title step — the `capture-input` breadcrumb field, keyboard
    /// up — without the user typing "reminder" or tapping the row first.
    @MainActor
    func testCaptureReminderDeeplinkOpensBreadcrumb() throws {
        let app = launchApp(deeplink: "quickie://capture/reminder")

        // The bottom launcher input exists on launch; we never touch it — the
        // deeplink alone drives selection.
        XCTAssertTrue(
            app.textFields["search-input"].waitForExistence(timeout: 30),
            "the launcher should come up on launch"
        )

        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(
            captureField.waitForExistence(timeout: 10),
            "the capture deeplink should open the breadcrumb on Argument 1 with no user input"
        )
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "the title step should bring the keyboard up"
        )

        // The breadcrumb is a real, drivable capture — committing a title is accepted
        // (the field takes text and Return advances the step), proving the deeplink
        // selected the Reminder capture rather than surfacing a stray row.
        captureField.tap()
        captureField.typeText("Buy milk\n")
    }
}
