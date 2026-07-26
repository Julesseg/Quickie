import XCTest

/// The Computed provider's **Date & time** surfaces (issues #210/#212;
/// CONTEXT.md → Date & time; ADR 0036), verifiable only by driving the real
/// app: typing a relative date phrase surfaces the boosted copy-only date row,
/// an until/since question surfaces the count row with full Calculator
/// manners, a timezone conversion surfaces the copy-only time row, and the
/// Date & time toggle on the Computed page suppresses exactly those rows
/// through the rebuilt engine. The grammar itself — anchors, tables, zones,
/// the injected clock — is covered deterministically by QuickieCore's
/// DateGrammarTests / ComputedDateTimeTests; these verify the wiring from a
/// typed query through the loop to the rendered rows, and from a rendered
/// toggle through `@AppStorage` back to the loop.
///
/// Every launch passes `-uitest-reset-signals` for a clean, all-enabled slate,
/// as the other provider-page suites do.
final class DateTimeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    @MainActor
    private func type(_ text: String, into app: XCUIApplication, clearing count: Int = 0) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist")
        input.tap()
        if count > 0 {
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        input.typeText(text)
    }

    @MainActor
    private func openProviderPage(_ app: XCUIApplication, typing name: String, row: String, clearing count: Int = 0) {
        type(name, into: app, clearing: count)
        let command = app.buttons[row]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing '\(name)' surfaces the \(row) command row")
        command.tap()
    }

    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    /// Flips a schema toggle to `on`/`off` and asserts it landed — the same
    /// tap-the-nested-switch-else-trailing-coordinate approach the schema suites use.
    @MainActor
    private func flip(_ identifier: String, to on: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the \(identifier) toggle renders from the schema")

        let landed = NSPredicate(format: "value == %@", on ? "1" : "0")
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3) != .completed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "the tap flipped \(identifier) \(on ? "on" : "off")")
    }

    /// A relative date phrase, an until/since question, and a timezone
    /// conversion each surface their boosted row — the date answer as
    /// `date.relative`, the count answer as `date.count` (issue #210 AC #1,
    /// #2), the converted time as `date.timezone` (issue #212 AC #1). The
    /// toggle defaults on, so this is the out-of-the-box behavior.
    @MainActor
    func testDateRowsSurfaceByDefault() throws {
        let app = launchApp()

        // Relative arithmetic → a boosted date-answer row.
        type("3 weeks from friday", into: app)
        XCTAssertTrue(app.buttons["date.relative"].waitForExistence(timeout: 5),
                      "a relative date phrase surfaces the date-answer row")

        // An until/since question → a boosted count row.
        type("days until dec 25", into: app, clearing: 19)
        XCTAssertTrue(app.buttons["date.count"].waitForExistence(timeout: 5),
                      "an until question surfaces the count row")

        // A timezone conversion → a boosted copy-only time row.
        type("9am pst in tokyo", into: app, clearing: 17)
        XCTAssertTrue(app.buttons["date.timezone"].waitForExistence(timeout: 5),
                      "a timezone conversion surfaces the converted-time row")
    }

    /// A date answer's long-press menu offers the universal Copy / Share and —
    /// since it is a bare terminal value, not a stored record — never Edit
    /// (issue #210 AC #3; CONTEXT.md → Stage). The copied text and the copy-only
    /// (never staging) main action are pinned deterministically in QuickieCore's
    /// ComputedDateTimeTests; this verifies the menu shape.
    @MainActor
    func testDateRowOffersCopyShareNoEdit() throws {
        let app = launchApp()

        type("2 days ago", into: app)
        let row = app.buttons["date.relative"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a relative date phrase surfaces the date-answer row")
        row.press(forDuration: 1.3)

        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5),
                      "a date row's menu offers Copy (the locale-formatted date)")
        XCTAssertTrue(app.buttons["Share"].exists,
                      "a date row's menu offers Share")
        XCTAssertFalse(app.buttons["Edit"].exists,
                       "a date answer is a bare value, not a stored record — no Edit")
    }

    /// The Computed page's Options section renders the Date & time toggle, and
    /// flipping it off suppresses all three grammar families — the date answer,
    /// the count answer, *and* the converted time (issue #212 rides the same
    /// toggle, no setting of its own) — while arithmetic still answers: the
    /// toggle takes effect on the rebuilt loop, not just in the UI (issue #210
    /// AC #6, issue #212 AC #5).
    @MainActor
    func testDateTimeToggleSuppressesBothFamiliesAndRestores() throws {
        let app = launchApp()

        // On (the default): the date row surfaces.
        type("3 weeks from friday", into: app)
        XCTAssertTrue(app.buttons["date.relative"].waitForExistence(timeout: 5),
                      "with Date & time on, a relative phrase surfaces its row")

        // Flip the Date & time toggle off on the Computed page (reached by its
        // "calculator" typed alias, which the persisted id keeps).
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 19)
        flip("setting-calculator.dateTime", to: false, in: app)
        goBackHome(app)

        // Off: both families are gone — relative arithmetic and until/since —
        // but arithmetic is untouched, proving the toggle gates only the date grammar.
        type("3 weeks from friday", into: app, clearing: 10)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["date.relative"].exists,
                       "with Date & time off, the date-answer row must be gone")

        type("days until dec 25", into: app, clearing: 19)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["date.count"].exists,
                       "with Date & time off, the count row must be gone")

        type("9am pst in tokyo", into: app, clearing: 17)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["date.timezone"].exists,
                       "with Date & time off, the converted-time row must be gone")

        type("5+5", into: app, clearing: 16)
        XCTAssertTrue(app.buttons["calc.math"].waitForExistence(timeout: 5),
                      "arithmetic is untouched by the Date & time toggle")

        // Restore the default so a persisted store never leaks an off toggle into
        // a later run of this suite.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 3)
        flip("setting-calculator.dateTime", to: true, in: app)
        goBackHome(app)
    }
}
