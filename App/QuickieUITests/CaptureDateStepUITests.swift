import XCTest

/// The date step's keyboard-less layout (the MultiStepAction date input):
/// advancing the breadcrumb from the title step to the due-date step removes the
/// text field, so the keyboard drops — a *structural* dismissal, unlike the
/// transient context-menu resignation the launcher's held inset exists for
/// (issue #58). The launcher must release that held inset so the date picker and
/// its commit button take the keyboard's space, rather than staying frozen a
/// keyboard-height above a dead band.
///
/// XCUITest cannot pre-grant the simulator's Reminders permission dialog, so the
/// run uses the `-uitest-stub-reminders` seam: the real `Action.newReminder`
/// breadcrumb with only the EventKit edge stubbed (see `UITestReminderCapture`).
final class CaptureDateStepUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Clean in-memory + signals slate (mirrors the other UI suites), plus the
        // stubbed reminder capture so the breadcrumb starts without a permission
        // dialog.
        app.launchArguments += ["--uitesting", "-uitest-reset-signals", "-uitest-stub-reminders"]
        app.launch()
        return app
    }

    /// Advances a New Reminder capture onto its due-date step and returns the app.
    /// Leaves the capture showing the date picker with the keyboard down.
    @MainActor
    private func advanceToDateStep(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        input.typeText("reminder")

        let row = app.buttons["builtin.new-reminder"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing surfaces the New Reminder row")
        row.tap()

        // Title step: the capture field auto-focuses, keyboard up. Commit a title
        // via Return.
        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(captureField.waitForExistence(timeout: 5), "the breadcrumb starts on the title step")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "the title step brings the keyboard up"
        )
        captureField.tap()
        captureField.typeText("Buy milk\n")
    }

    /// The due-date step drops the keyboard *and the layout follows*: the "Set Due
    /// Date" commit button settles at the bottom of the screen where the input bar
    /// lives, not held a keyboard-height up over empty space — the frozen inset of
    /// issue #58 must release for a keyboard-less step.
    @MainActor
    func testDateStepTakesKeyboardSpace() throws {
        let app = launchApp()
        advanceToDateStep(app)

        let setDate = app.buttons["capture-set-date"]
        XCTAssertTrue(setDate.waitForExistence(timeout: 5), "committing the title advances to the due-date step")
        XCTAssertTrue(
            app.datePickers.firstMatch.waitForExistence(timeout: 5),
            "the due-date step shows the inline date picker"
        )
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "the due-date step has no text field, so the keyboard drops"
        )

        // The commit button must follow the keyboard down to the bottom of the
        // screen. The held inset only ever comes from a >120pt keyboard overlap,
        // so a 120pt tolerance cleanly separates "released" (home indicator +
        // padding) from "frozen" (a ~300pt phantom keyboard) without hardcoding a
        // device's exact metrics. Poll briefly so the 0.25s release animation has
        // settled before the frame is judged.
        let deadline = Date().addingTimeInterval(5)
        var bottomGap = CGFloat.greatestFiniteMagnitude
        repeat {
            bottomGap = app.frame.maxY - setDate.frame.maxY
            if bottomGap <= 120 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        XCTAssertLessThanOrEqual(
            bottomGap, 120,
            "the date step must take the keyboard's space — the Set button sat \(bottomGap)pt above the bottom (held inset not released)"
        )
    }

    /// Committing the date moves on to the list step, whose fuzzy filter brings
    /// the keyboard straight back — the release must be one step's worth, not a
    /// permanent unlock of the held-inset behaviour.
    @MainActor
    func testCommittingDateRestoresKeyboardForNextStep() throws {
        let app = launchApp()
        advanceToDateStep(app)

        let setDate = app.buttons["capture-set-date"]
        XCTAssertTrue(setDate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        setDate.tap()

        // List step: the capture field returns, auto-focuses, and the keyboard
        // rises again.
        XCTAssertTrue(
            app.textFields["capture-input"].waitForExistence(timeout: 5),
            "committing the date advances to the list step's filter field"
        )
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "the list step's filter field brings the keyboard back up"
        )
    }
}
