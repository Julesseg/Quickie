import XCTest

/// The Computed provider's **Detected result** surfaces (CONTEXT.md → Detected
/// result; ADR 0032), verifiable only by driving the real app: typing a whole-
/// query URL / phone number / email surfaces the boosted Open / Message + Call /
/// Email rows, and each per-type toggle on the Computed page suppresses exactly
/// its rows through the rebuilt engine. The detection logic itself — the parse
/// boundary, the row shapes, the toggle gating — is covered deterministically by
/// QuickieCore's TypedContentDetectionTests / ComputedDetectionTests; these verify
/// the wiring from a typed query through the loop to the rendered rows, and from a
/// rendered toggle through `@AppStorage` back to the loop.
///
/// Every launch passes `-uitest-reset-signals` for a clean, all-enabled slate, as
/// the other provider-page suites do.
final class ComputedDetectionUITests: XCTestCase {

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

    /// A whole-query URL, phone number, and email each surface their boosted rows —
    /// Open for a URL, Message + Call for a phone number, Email for an address (AC #1,
    /// #2). All detection toggles default on, so this is the out-of-the-box behavior.
    @MainActor
    func testDetectedRowsSurfaceByDefault() throws {
        let app = launchApp()

        // A bare domain → one Open row.
        type("apple.com", into: app)
        XCTAssertTrue(app.buttons["detect.url"].waitForExistence(timeout: 5),
                      "a bare domain surfaces the Open row")

        // An email address → one Email row.
        type("me@work.com", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["detect.email"].waitForExistence(timeout: 5),
                      "an email address surfaces the Email row")

        // A phone number → two rows, Message nearest the thumb and Call above it.
        type("555 123 4567", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["detect.phone.message"].waitForExistence(timeout: 5),
                      "a phone number surfaces the Message row")
        XCTAssertTrue(app.buttons["detect.phone.call"].waitForExistence(timeout: 5),
                      "a phone number surfaces the Call row")
    }

    /// A detected row's long-press menu offers the universal Copy / Share and — since
    /// it is a bare value, not a stored record — never Edit (AC #3, CONTEXT.md →
    /// Detected result). The copied *value* (bare number/address, not the scheme URL)
    /// is pinned deterministically in QuickieCore's tests; this verifies the menu shape.
    @MainActor
    func testDetectedRowOffersCopyShareNoEdit() throws {
        let app = launchApp()

        type("me@work.com", into: app)
        let row = app.buttons["detect.email"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "an email address surfaces the Email row")
        row.press(forDuration: 1.3)

        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5),
                      "a detected row's menu offers Copy (its bare value)")
        XCTAssertTrue(app.buttons["Share"].exists,
                      "a detected row's menu offers Share")
        XCTAssertFalse(app.buttons["Edit"].exists,
                       "a detected row is a bare value, not a stored record — no Edit")
    }

    /// The Computed page's Options section renders a detection toggle (URLs), and
    /// flipping it off suppresses exactly the Open row while arithmetic still answers
    /// — the toggle takes effect on the rebuilt loop, not just in the UI (AC #6).
    @MainActor
    func testURLToggleSuppressesOnlyItsRowAndRestores() throws {
        let app = launchApp()

        // On (the default): a bare domain injects the Open row.
        type("apple.com", into: app)
        XCTAssertTrue(app.buttons["detect.url"].waitForExistence(timeout: 5),
                      "with URLs on, 'apple.com' injects the Open row")

        // Flip the URLs detection toggle off on the Computed page (reached by its
        // "calculator" typed alias, which the persisted id keeps).
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 20)
        flip("setting-calculator.url", to: false, in: app)
        goBackHome(app)

        // Off: the Open row is gone, but arithmetic is untouched — proving the toggle
        // gates only URL detection, through to the rebuilt engine.
        type("apple.com", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["detect.url"].exists,
                       "with URLs off, the Open row must be gone")

        type("5+5", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["calc.math"].waitForExistence(timeout: 5),
                      "arithmetic is untouched by the URL detection toggle")

        // Restore the default so a persisted store never leaks an off toggle into a
        // later run of this suite.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 20)
        flip("setting-calculator.url", to: true, in: app)
        goBackHome(app)
    }
}
