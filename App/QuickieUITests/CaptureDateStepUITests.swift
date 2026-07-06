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
    /// date re-creates the date step already collecting a time. The step used to
    /// re-enter a `UIDatePicker` *built* in `.dateAndTime`, whose fresh inline
    /// layout shifts the calendar down under a blank band and squashes the time
    /// row; the calendar is date-only now with the time as its own compact row,
    /// so re-entry must be pixel-identical to the forward path: the calendar's
    /// month-navigation header sits at the same offset inside the picker, and
    /// the Time row sits fully below the calendar — never squashed into it.
    @MainActor
    func testBackspaceOntoTimedDateKeepsCalendarAligned() throws {
        let app = launchApp()
        advanceToDateStep(app)

        let calendar = app.datePickers["capture-calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "the due-date step shows the inline calendar")

        // The grid's row pitch on first display — the reference the re-entered
        // calendar must reproduce. Let the entry animation settle first.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let freshPitch = rowPitch(in: calendar)
        XCTAssertGreaterThan(
            freshPitch, 10,
            "the pitch measurement must find the calendar's day cells — a 0 here means the cell query broke, not that the layout is fine"
        )

        // Move the selection off today so the re-entered step seeds a genuinely
        // committed (non-default) date, and record the pitch again — a selection
        // change is the historic trigger for the calendar compacting its rows.
        let dayLabel = Calendar.current.component(.day, from: Date()) == 15 ? "16" : "15"
        let day = dayCell(dayLabel, in: calendar)
        XCTAssertTrue(day.waitForExistence(timeout: 5), "the calendar shows day \(dayLabel) of the current month")
        day.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let afterTapPitch = rowPitch(in: calendar)
        NSLog("CAPTURE-CALENDAR-PITCH fresh=%.2f afterTap=%.2f", freshPitch, afterTapPitch)
        XCTAssertEqual(
            afterTapPitch, freshPitch, accuracy: 3,
            "tapping a day must not compact the calendar rows — pitch went \(freshPitch)pt → \(afterTapPitch)pt"
        )

        // Include a time via the toggle — the forward-entered reference layout.
        // The row-spanning switch element's center can miss the control, so tap
        // the nested switch when the OS exposes one and fall back to a
        // trailing-edge coordinate tap otherwise.
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

        let time = app.descendants(matching: .any)["capture-time"].firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 5), "including a time adds the Time row")

        let header = calendar.buttons["Next Month"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "the inline calendar exposes its month-navigation header")
        // Let the layout settle before recording the reference geometry.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let forwardOffset = header.frame.minY - calendar.frame.minY
        XCTAssertGreaterThanOrEqual(
            time.frame.minY, calendar.frame.maxY - 1,
            "the Time row must sit fully below the calendar"
        )

        // Commit the timed date, then backspace on the empty list filter to land
        // back on the due-date step — the timed step is re-entered fresh.
        app.buttons["capture-set-date"].tap()
        let filter = app.textFields["capture-input"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "committing the date advances to the list step")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        filter.typeText(XCUIKeyboardKey.delete.rawValue)

        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "backspace re-enters the due-date step")
        XCTAssertTrue(time.waitForExistence(timeout: 5), "a timed date re-enters with its Time row")
        XCTAssertTrue(header.waitForExistence(timeout: 5))

        // Poll briefly so the re-entry transition settles before the frame is
        // judged. The broken fresh-built `.dateAndTime` layout shifted the grid
        // ~40pt, so a 15pt tolerance separates it cleanly from render jitter.
        let deadline = Date().addingTimeInterval(5)
        var reenteredOffset = CGFloat.greatestFiniteMagnitude
        repeat {
            reenteredOffset = header.frame.minY - calendar.frame.minY
            if abs(reenteredOffset - forwardOffset) <= 15 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        XCTAssertEqual(
            reenteredOffset, forwardOffset, accuracy: 15,
            "a re-entered timed date step must match the forward-entered layout — the calendar header sat \(reenteredOffset)pt into the picker vs \(forwardOffset)pt (blank band above the grid)"
        )
        XCTAssertGreaterThanOrEqual(
            time.frame.minY, calendar.frame.maxY - 1,
            "the re-entered Time row must sit fully below the calendar, not squashed into it"
        )

        // The re-entered grid must keep the first display's row pitch — rows
        // drawing closer together is the calendar compacting inside its pinned
        // height.
        let reenteredPitch = rowPitch(in: calendar)
        NSLog("CAPTURE-CALENDAR-PITCH fresh=%.2f reentered=%.2f", freshPitch, reenteredPitch)
        XCTAssertEqual(
            reenteredPitch, freshPitch, accuracy: 3,
            "the re-entered calendar compacted its rows — pitch \(freshPitch)pt on first display vs \(reenteredPitch)pt on re-entry"
        )
    }

    /// The vertical distance between consecutive week rows of the inline
    /// calendar, measured from the day-number cells two weeks apart (present in
    /// every month layout) so a single missing edge day can't skew it. Returns
    /// half the 8→22 distance; 0 if the cells can't be found.
    @MainActor
    private func rowPitch(in calendar: XCUIElement) -> CGFloat {
        let top = dayCell("8", in: calendar)
        let bottom = dayCell("22", in: calendar)
        guard top.exists, bottom.exists else { return 0 }
        return (bottom.frame.minY - top.frame.minY) / 2
    }

    /// A day-number cell of the inline calendar. The OS has exposed these as
    /// different element types across versions, so match by exact label across
    /// any type rather than assuming staticText.
    @MainActor
    private func dayCell(_ label: String, in calendar: XCUIElement) -> XCUIElement {
        calendar.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
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
