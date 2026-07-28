import XCTest

/// The Computed provider's **Detected result** surfaces (CONTEXT.md → Detected
/// result; ADR 0032; issue #217), verifiable only by driving the real app: typing a
/// whole-query URL / phone number / email / hex color surfaces the boosted Open /
/// Message + Call / Email / Copy rows, and each per-type toggle on the Computed
/// page suppresses exactly its rows through the rebuilt engine. The detection logic itself — the parse
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
    ///
    /// The Computed options section now runs **seven** toggles deep (issue #217) and
    /// Form rows render lazily, so a toggle low in the list — Colors, the last —
    /// is scrolled into existence first, the same way the hub suite reaches its
    /// bottom provider rows.
    @MainActor
    private func flip(_ identifier: String, to on: Bool, in app: XCUIApplication) {
        // Math is the first per-type toggle, so its arrival means the options
        // section has rendered and it is safe to start scrolling toward the target.
        XCTAssertTrue(app.switches["setting-calculator.math"].waitForExistence(timeout: 10),
                      "the Computed page renders its options section")
        let toggle = app.switches[identifier]
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.exists, "the \(identifier) toggle renders from the schema")

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

    /// A whole-query hex color — 3-, 6-, and 8-digit — surfaces its boosted **Copy**
    /// row subtitled with the typed value, while a bare hex run without the `#` fires
    /// nothing (AC #1, #2). Colors defaults on, so this is out-of-the-box behavior.
    @MainActor
    func testHexColorSurfacesCopyRowAndBareRunDoesNot() throws {
        let app = launchApp()

        for typed in ["#f60", "#ff6600", "#ff6600cc"] {
            type(typed, into: app, clearing: 20)
            let row = app.buttons["detect.color"]
            XCTAssertTrue(row.waitForExistence(timeout: 5),
                          "'\(typed)' surfaces the Copy row")
            // Verb-titled "Copy", subtitled with the typed value — both ride the
            // button's merged accessibility label.
            XCTAssertTrue(row.label.contains("Copy"), "the row is verb-titled Copy (label: \(row.label))")
            XCTAssertTrue(row.label.contains(typed),
                          "the row is subtitled with the typed value '\(typed)' (label: \(row.label))")
        }

        // The `#` is required — a bare hex run fails the never-a-guess bar.
        type("ff6600", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["detect.color"].exists,
                       "a bare hex run without '#' must not surface a color row")
    }

    /// The color row is a bare value like its Detected siblings: Copy / Share, never
    /// Edit (AC #3). Its copy-only, non-staging outcome is pinned deterministically in
    /// QuickieCore; this verifies the rendered menu shape.
    @MainActor
    func testColorRowOffersCopyShareNoEdit() throws {
        let app = launchApp()

        type("#ff6600", into: app)
        let row = app.buttons["detect.color"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a hex color surfaces the Copy row")
        row.press(forDuration: 1.3)

        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5),
                      "a color row's menu offers Copy (its bare value)")
        XCTAssertTrue(app.buttons["Share"].exists, "a color row's menu offers Share")
        XCTAssertFalse(app.buttons["Edit"].exists,
                       "a color row is a bare value, not a stored record — no Edit")
    }

    /// The Computed page's Options section renders the **Colors** toggle — the seventh
    /// of the roster — and flipping it off suppresses exactly the color row while the
    /// other detections keep answering (AC #5).
    @MainActor
    func testColorsToggleSuppressesOnlyItsRowAndRestores() throws {
        let app = launchApp()

        // On (the default): a hex color injects the Copy row.
        type("#ff6600", into: app)
        XCTAssertTrue(app.buttons["detect.color"].waitForExistence(timeout: 5),
                      "with Colors on, '#ff6600' injects the Copy row")

        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 20)
        flip("setting-calculator.color", to: false, in: app)
        goBackHome(app)

        // Off: the color row is gone, but URL detection is untouched — proving the
        // toggle gates only colors, through to the rebuilt engine.
        type("#ff6600", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders before asserting the absence")
        XCTAssertFalse(app.buttons["detect.color"].exists,
                       "with Colors off, the Copy row must be gone")

        type("apple.com", into: app, clearing: 20)
        XCTAssertTrue(app.buttons["detect.url"].waitForExistence(timeout: 5),
                      "URL detection is untouched by the Colors toggle")

        // Restore the default so a persisted store never leaks an off toggle into a
        // later run of this suite.
        openProviderPage(app, typing: "calculator", row: "builtin.calculator-page", clearing: 20)
        flip("setting-calculator.color", to: true, in: app)
        goBackHome(app)
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
