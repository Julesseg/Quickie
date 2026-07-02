import XCTest

/// The provider-level Enabled toggle's acceptance criteria (issue #67) that can
/// only be observed by driving the real app: flipping a provider's Enabled off
/// on its page removes its contributions from typed results and the Favorites
/// grid, the provider stays re-enableable by typing its name, and flipping it
/// back on restores everything. The filtering *logic* — kind-level enablement,
/// the engine's exclusions, the kept pin — is covered deterministically by
/// QuickieCore's ProviderDisableTests; these verify the wiring from the toggle
/// through the persisted store to the rendered surfaces.
///
/// Every launch passes `-uitest-reset-signals`: the switches persist in the App
/// Group defaults, so a test that disables a provider must start (and leave
/// every later test starting) from the all-enabled slate.
final class ProviderDisableUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-signals"] + arguments
        app.launch()
        return app
    }

    /// Types into the auto-focused launcher input, clearing anything left from
    /// an earlier step first (popping a page clears the query, but a mid-test
    /// assertion may have left text behind).
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

    /// Opens a provider's page by typing its name and tapping its settings
    /// command row — the same typed route a user recovers a disabled provider
    /// through, so navigating this way *is* part of the acceptance.
    @MainActor
    private func openProviderPage(_ app: XCUIApplication, typing name: String, row: String, clearing count: Int = 0) {
        type(name, into: app, clearing: count)
        let command = app.buttons[row]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing '\(name)' surfaces the \(row) command row")
        command.tap()
    }

    /// Pops the pushed provider page back to the launcher. Opening a page
    /// cleared the query, so this lands on Home.
    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    /// Flips a provider page's Enabled toggle to `on`/`off` and asserts it
    /// landed. Tapping the row-spanning switch element's center misses the
    /// control (as in AppSettingsUITests), so tap the nested switch when the OS
    /// exposes one, falling back to a trailing-edge coordinate tap.
    @MainActor
    private func flip(_ provider: String, to on: Bool, in app: XCUIApplication) {
        let toggle = app.switches["provider-enabled-\(provider)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the \(provider) page leads with its Enabled toggle")

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
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "the tap flipped the toggle \(on ? "on" : "off")")
    }

    /// Disabling Calculator removes its injected result from typed results, its
    /// settings command row keeps answering its name (the typed recovery path),
    /// and re-enabling restores the result (AC #1, #2) — the Enabled toggle
    /// defaulting to on along the way.
    @MainActor
    func testDisablingCalculatorRemovesItsResultsAndReEnablingRestoresThem() throws {
        let app = launchApp()

        // Enabled (the default): a math query injects the boosted answer row.
        type("5+5", into: app)
        XCTAssertTrue(app.buttons["calc.math"].waitForExistence(timeout: 5),
                      "with Calculator enabled, '5+5' injects the math result")

        // Its page leads with the Enabled toggle, on by default; flip it off.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 3)
        flip("calculator", to: false, in: app)
        goBackHome(app)

        // Disabled: the same query injects nothing.
        type("5+5", into: app)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders (its fallbacks remain) before asserting the absence")
        XCTAssertFalse(app.buttons["calc.math"].exists,
                       "with Calculator disabled, '5+5' must inject no math result")

        // Still re-enableable by typing its name: the settings command row is
        // the recovery path, so it survives the disable. Flip it back on.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 3)
        flip("calculator", to: true, in: app)
        goBackHome(app)

        // Re-enabled: the result returns.
        type("5+5", into: app)
        XCTAssertTrue(app.buttons["calc.math"].waitForExistence(timeout: 5),
                      "re-enabling Calculator restores the math result")
    }

    /// Disabling a provider whose action is pinned drops the card from the
    /// Favorites grid without losing the pin: re-enabling brings the card back
    /// (AC #3). New Reminder is the pinned action — a built-in of the Reminders
    /// kind, so no stored content is needed.
    @MainActor
    func testDisabledFavoriteDropsFromTheGridAndReturnsOnReEnable() throws {
        let app = launchApp(arguments: ["-uitest-pin-favorite", "builtin.new-reminder"])

        // The seeded pin renders its card on Home.
        let card = app.buttons["favorite.builtin.new-reminder"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "the pinned New Reminder renders a Favorites card on Home")

        // Disable the Reminders provider from its page.
        openProviderPage(app, typing: "reminders", row: "builtin.reminders-page")
        flip("reminders", to: false, in: app)
        goBackHome(app)

        // The card is gone — but nothing was unpinned; only the surface hides.
        let placeholderOrRecents = app.descendants(matching: .any)["search-input"].firstMatch
        XCTAssertTrue(placeholderOrRecents.waitForExistence(timeout: 10), "back on the launcher")
        XCTAssertFalse(card.exists,
                       "disabling Reminders drops the pinned New Reminder from the grid")

        // Re-enable: the kept pin renders its card again, in its old slot.
        openProviderPage(app, typing: "reminders", row: "builtin.reminders-page")
        flip("reminders", to: true, in: app)
        goBackHome(app)

        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "re-enabling Reminders restores the pinned card — the pin survived the disable")
    }
}
