import XCTest

/// The return trip from a pushed management page (ADR 0012's zero-wall promise
/// extended to the pop): the keyboard rises once beneath the re-added input and
/// then **stays** up. The regression this locks down: the keyboard came up during
/// the pop transition, then flicked away and slid back up from the bottom once
/// the pop completed — the popped page's `onDisappear` refocus toggling an
/// already-taken focus off and on.
///
/// XCUITest can only snapshot `app.keyboards` at polling speed, which misses the
/// fast hide-then-show entirely, so the assertion reads the
/// `-uitest-keyboard-probe` seam instead: a hidden in-app counter of
/// `keyboardWillHide` notifications. Once the keyboard is back up after the pop,
/// that counter must never move again.
final class ReturnRefocusUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-reset-signals",
            "-uitest-instant-motion",
            "--uitesting",
            "-uitest-keyboard-probe",
        ]
        app.launch()
        return app
    }

    /// Reads the probe's current hide count off its accessibility label
    /// (`keyboard-hides:<n>`).
    @MainActor
    private func hideCount(_ app: XCUIApplication) -> Int {
        let probe = app.staticTexts["uitest-keyboard-hide-count"]
        guard probe.exists,
              let raw = probe.label.split(separator: ":").last,
              let count = Int(raw)
        else { return -1 }
        return count
    }

    /// Pushing Settings drops the keyboard once; popping back re-raises it and it
    /// must then stay up — no further `keyboardWillHide` while the launcher settles.
    @MainActor
    func testKeyboardStaysUpAfterPoppingBackFromSettings() throws {
        let app = launchApp()

        // Type "settings" and push the Settings page, as AppSettingsUITests does.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        input.typeText("settings")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'settings' surfaces the Settings command")

        // Take the baseline *before* pushing — the probe lives on the launcher
        // root, which a pushed page removes from the accessibility tree, so this
        // is the last race-free read. The push then adds exactly one legitimate
        // hide; the pop adds none. Anything past baseline + 1 is the flicker.
        let baseline = hideCount(app)
        XCTAssertGreaterThanOrEqual(baseline, 0, "the probe is armed and readable on the launcher")

        row.tap()

        // The push removes the input, dropping the keyboard (the expected hide).
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "pushing Settings drops the keyboard"
        )

        // Pop back to the launcher.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed Settings page shows a back button")
        back.tap()

        // The keyboard comes back up beneath the re-added input.
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "popping back re-raises the keyboard"
        )

        // Watch the probe across the settle window: the count must hold at
        // baseline + 1 (the push's hide) — one more means the keyboard dropped
        // again after the pop re-raised it.
        let allowed = baseline + 1
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let now = hideCount(app)
            XCTAssertLessThanOrEqual(
                now, allowed,
                "the keyboard flickered after the pop: keyboardWillHide fired again (\(now) vs allowed \(allowed))"
            )
            usleep(150_000)
        }

        // And the keyboard is still up at the end of the window.
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard is still up after settling")
    }
}
