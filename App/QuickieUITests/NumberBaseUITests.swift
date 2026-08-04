import XCTest

/// The Computed provider's **base notation** surfaces (issue #216; CONTEXT.md →
/// Computed), verifiable only by driving the real app: a `0x`/`0b` literal
/// inside arithmetic answers through the ordinary math row, an explicit
/// "255 to hex" surfaces its own prefixed row, a bare prefixed literal fires its
/// decimal row where a bare number fires nothing, and the existing **Math**
/// toggle — no new setting — suppresses all three through the rebuilt engine.
/// The grammar itself (radices, base names, connectors, every decline) is
/// covered deterministically by QuickieCore's NumberBasesTests /
/// ComputedBasesTests; these verify the wiring from a typed query through the
/// loop to the rendered rows, and from a rendered toggle back to the loop.
///
/// Every launch passes `-uitest-reset-signals` for a clean, all-enabled slate,
/// as the other provider-page suites do.
final class NumberBaseUITests: XCTestCase {

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

    /// Arithmetic over a base literal, an explicit conversion, and a bare
    /// prefixed literal each surface their boosted row — the first through the
    /// ordinary `calc.math` row with a decimal answer (AC #1), the conversion as
    /// `calc.base` showing the prefixed answer (AC #2), the lone literal as
    /// `calc.literal` showing its decimal value (AC #4). The Math toggle
    /// defaults on, so this is the out-of-the-box behavior.
    @MainActor
    func testBaseRowsSurfaceByDefault() throws {
        let app = launchApp()

        type("0xff + 1", into: app)
        let math = app.buttons["calc.math"]
        XCTAssertTrue(math.waitForExistence(timeout: 5),
                      "a base literal inside arithmetic answers through the math row")
        XCTAssertTrue(math.label.contains("256"),
                      "the answer to '0xff + 1' reads as decimal 256 (label: \(math.label))")

        type("255 to hex", into: app, clearing: 8)
        let conversion = app.buttons["calc.base"]
        XCTAssertTrue(conversion.waitForExistence(timeout: 5),
                      "an explicit base conversion surfaces its own row")
        XCTAssertTrue(conversion.label.contains("0xFF"),
                      "the conversion answers prefixed, so the staged text is unambiguous (label: \(conversion.label))")

        type("0xff", into: app, clearing: 10)
        let literal = app.buttons["calc.literal"]
        XCTAssertTrue(literal.waitForExistence(timeout: 5),
                      "a bare prefixed literal is an explicit notation act — it fires its decimal row")
        XCTAssertTrue(literal.label.contains("255"),
                      "the bare literal's row shows its decimal value (label: \(literal.label))")
    }

    /// A bare number stays inert (AC #4): typing `42` fires no Computed row at
    /// all, which is what the prefixed-literal rule above is carved out of.
    @MainActor
    func testBareNumberStillFiresNothing() throws {
        let app = launchApp()

        type("42", into: app)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["calc.literal"].exists,
                       "a plain digit run is not a notation act — no decimal row")
        XCTAssertFalse(app.buttons["calc.math"].exists,
                       "a bare number is not a calculation either")
    }

    /// The existing **Math** toggle gates every base row — arithmetic over
    /// literals, the explicit conversion, and the lone literal — with no setting
    /// of its own (AC #7), and unit conversions are untouched, since the two
    /// `to` grammars never arbitrate (AC #3).
    @MainActor
    func testMathToggleGatesBaseRowsAndRestores() throws {
        let app = launchApp()

        // On (the default): the conversion row surfaces.
        type("255 to hex", into: app)
        XCTAssertTrue(app.buttons["calc.base"].waitForExistence(timeout: 5),
                      "with Math on, an explicit base conversion surfaces its row")

        // Flip Math off on the Computed page (reached by its "calculator" typed
        // alias, which the persisted id keeps).
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 10)
        flip("setting-calculator.math", to: false, in: app)
        goBackHome(app)

        // Off: all three base rows are gone…
        type("255 to hex", into: app, clearing: 10)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["calc.base"].exists,
                       "with Math off, the base-conversion row must be gone")

        type("0xff", into: app, clearing: 10)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["calc.literal"].exists,
                       "with Math off, the bare-literal row must be gone")

        type("0xff + 1", into: app, clearing: 4)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["calc.math"].exists,
                       "with Math off, arithmetic over literals is gone with the rest of math")

        // …while a unit conversion still answers: bases ride the Math toggle,
        // units ride theirs, and the shared `to` needs no arbitration.
        type("20 mi to km", into: app, clearing: 8)
        XCTAssertTrue(app.buttons["calc.conversion"].waitForExistence(timeout: 5),
                      "unit conversion is untouched by the Math toggle")

        // Restore the default so a persisted store never leaks an off toggle into
        // a later run of this suite.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 11)
        flip("setting-calculator.math", to: true, in: app)
        goBackHome(app)
    }
}
