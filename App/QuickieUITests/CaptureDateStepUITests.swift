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
        app.launchArguments.append("-uitest-instant-motion")
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

    /// Backspacing from the list step onto an already-committed **timed** due
    /// date re-creates the inline picker directly in date+time mode. A
    /// `UIDatePicker` *built* in `.dateAndTime` settles taller than one grown
    /// into it via the toggle, so the pinned band used to shove the calendar
    /// down under a blank band and squash the time row. The picker must lay out
    /// like the grown one: its month-navigation header sits at the same offset
    /// from the picker's top on re-entry as it did after the toggle grew it.
    @MainActor
    func testBackspaceOntoTimedDateKeepsCalendarAligned() throws {
        let app = launchApp()
        advanceToDateStep(app)

        let picker = app.datePickers.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the due-date step shows the inline picker")

        // Grow into date+time via the toggle — the known-good layout the pinned
        // band is sized for. The row-spanning switch element's center can miss
        // the control, so tap the nested switch when the OS exposes one and fall
        // back to a trailing-edge coordinate tap otherwise.
        let toggle = app.switches["capture-include-time"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the reminder date step offers the time toggle")
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let isOn = NSPredicate(format: "value == '1'")
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isOn, object: toggle)], timeout: 3) != .completed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isOn, object: toggle)], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, "1", "the tap flipped the time toggle on")

        let header = picker.buttons["Next Month"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "the inline picker exposes its month-navigation header")
        // Let the mode-change relayout settle before recording the reference.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let grownOffset = header.frame.minY - picker.frame.minY

        // Commit the timed date, then backspace on the empty list filter to land
        // back on the due-date step — the picker is re-created already timed.
        app.buttons["capture-set-date"].tap()
        let filter = app.textFields["capture-input"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "committing the date advances to the list step")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        filter.typeText(XCUIKeyboardKey.delete.rawValue)

        XCTAssertTrue(picker.waitForExistence(timeout: 5), "backspace re-enters the due-date step")
        XCTAssertTrue(header.waitForExistence(timeout: 5))

        // Poll briefly so the re-entry transition settles before the frame is
        // judged. The broken fresh-built layout shifted the grid ~40pt, so a
        // 15pt tolerance separates it cleanly from render jitter.
        let deadline = Date().addingTimeInterval(5)
        var reenteredOffset = CGFloat.greatestFiniteMagnitude
        repeat {
            reenteredOffset = header.frame.minY - picker.frame.minY
            if abs(reenteredOffset - grownOffset) <= 15 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        XCTAssertEqual(
            reenteredOffset, grownOffset, accuracy: 15,
            "a re-entered timed date step must lay out like the grown picker — the calendar header sat \(reenteredOffset)pt into the picker vs \(grownOffset)pt (blank band above the grid, squashed time row)"
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
