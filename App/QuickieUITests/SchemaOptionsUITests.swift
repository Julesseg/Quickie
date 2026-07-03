import XCTest

/// The declared settings schema's generic renderer (ADR 0020; issue #69), verifiable
/// only by driving the real app: a provider page's Options section is drawn entirely
/// from `provider.settingsSchema`, so a schema-declared toggle / stepper appears with
/// no bespoke view, and a new option *takes effect* on the loop. The schema itself —
/// the option types, per-provider declarations, and the dynamic-choice mapping — is
/// covered deterministically by QuickieCore's SettingOptionTests; these verify the
/// wiring from a rendered control through `@AppStorage` to the rebuilt engine.
///
/// Every launch passes `-uitest-reset-signals` for a clean, all-enabled slate, as the
/// other provider-page suites do — the settings persist across runs otherwise.
final class SchemaOptionsUITests: XCTestCase {

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

    /// Opens a provider's page by typing its name and tapping its settings command row.
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
    /// tap-the-nested-switch-else-trailing-coordinate approach the Enabled toggle
    /// suite uses, since a row-spanning switch's center misses the control.
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

    /// The Calculator page's Options section renders the new unit-conversion toggle
    /// purely from the schema (AC #2, #4), and flipping it off stops the provider
    /// answering conversions while leaving arithmetic untouched — the option takes
    /// effect on the loop, not just in the UI.
    @MainActor
    func testCalculatorUnitConversionToggleRendersFromSchemaAndTakesEffect() throws {
        let app = launchApp()

        // Enabled (the default): a unit-conversion query injects the boosted answer.
        type("20 mi to km", into: app)
        XCTAssertTrue(app.buttons["calc.conversion"].waitForExistence(timeout: 5),
                      "with unit conversion on, '20 mi to km' injects the conversion result")

        // Its page renders the schema's unit-conversion toggle; flip it off.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 11)
        flip("setting-calculator.unitConversion", to: false, in: app)
        goBackHome(app)

        // Off: the conversion query injects nothing, but arithmetic still answers —
        // proving the toggle gates only conversions, through to the rebuilt engine.
        type("20 mi to km", into: app)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["calc.conversion"].exists,
                       "with unit conversion off, the conversion result must be gone")

        type("5+5", into: app, clearing: 11)
        XCTAssertTrue(app.buttons["calc.math"].waitForExistence(timeout: 5),
                      "arithmetic is untouched by the unit-conversion toggle")
    }

    /// The File Search page's Options section renders the schema's inline-cap stepper
    /// (AC #2): the third option type, drawn generically with its default value shown.
    /// That the cap bounds inline rows is covered deterministically in Core.
    @MainActor
    func testFileSearchInlineCapStepperRendersFromSchema() throws {
        let app = launchApp()

        openProviderPage(app, typing: "file search", row: "builtin.file-search-page")

        let stepper = app.descendants(matching: .any)["setting-file-search.inlineCap"].firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 10),
                      "the File Search page renders the inline-cap stepper from the schema")
        // Its declared default (3) is shown beside the control.
        XCTAssertTrue(app.staticTexts["setting-file-search.inlineCap-value"].waitForExistence(timeout: 5),
                      "the stepper shows its current value")
    }
}
