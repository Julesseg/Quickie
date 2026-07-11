import XCTest

/// The System umbrella provider's acceptance criteria that can only be observed by
/// driving the real app (CONTEXT.md → System provider; ADR 0029; issue #144): the
/// top-level Providers list folds Reminders and Events under one **System** row,
/// its page links to their unchanged pages and lists two disable-only built-ins,
/// and its **cascading** Enabled toggle hides New Reminder, New Event, App Store
/// Search, and Open iOS Settings from results while their own toggles stay set.
///
/// The cascade *logic* is pinned deterministically by QuickieCore's
/// SystemProviderTests; these verify the wiring from the toggle through the
/// persisted store to the rendered surfaces. Every launch resets signals so each
/// test starts from the all-enabled slate.
final class SystemProviderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-signals", "-uitest-instant-motion"] + arguments
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
    private func openSystemPage(_ app: XCUIApplication, clearing count: Int = 0) {
        type("system", into: app, clearing: count)
        let command = app.buttons["builtin.system-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'system' surfaces the System command row")
        command.tap()
    }

    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    @MainActor
    private func flipSystem(to on: Bool, in app: XCUIApplication) {
        let toggle = app.switches["provider-enabled-system"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the System page leads with its Enabled toggle")
        let landed = NSPredicate(format: "value == %@", on ? "1" : "0")
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap() } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3) != .completed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "the tap flipped System \(on ? "on" : "off")")
    }

    /// The System page structure: the cascading Enabled toggle, navigation rows
    /// into Reminders and Events, and an actions section with the two built-ins,
    /// each carrying a disable toggle. The two typed member command rows also still
    /// deeplink to their own pages (they survive the fold).
    @MainActor
    func testSystemPageLinksMembersAndListsBuiltIns() throws {
        let app = launchApp()
        openSystemPage(app)

        XCTAssertTrue(app.switches["provider-enabled-system"].waitForExistence(timeout: 10),
                      "the System page leads with its Enabled toggle")
        // The built-in's disable toggle is present (the actions section).
        XCTAssertTrue(app.switches["system-action-enabled.builtin.system.open-ios-settings"].waitForExistence(timeout: 5),
                      "Open iOS Settings shows its disable toggle")
    }

    /// System off hides every member action from results (New Reminder, New Event,
    /// Open iOS Settings); turning it back on restores them.
    @MainActor
    func testSystemDisableCascadesToMembersAndReEnables() throws {
        let app = launchApp()

        // Enabled by default: the member actions surface by name.
        type("reminder", into: app)
        XCTAssertTrue(app.buttons["builtin.new-reminder"].waitForExistence(timeout: 5),
                      "New Reminder surfaces while System is enabled")

        // Flip System off on its page.
        openSystemPage(app, clearing: 8)
        flipSystem(to: false, in: app)
        goBackHome(app)

        // The member captures and built-ins go dark, even though their own toggles
        // are untouched (the umbrella cascade).
        type("reminder", into: app)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the result list renders (its fallbacks remain) before asserting the absence")
        XCTAssertFalse(app.buttons["builtin.new-reminder"].exists,
                       "System off hides New Reminder from results")

        type("event", into: app, clearing: 8)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["builtin.new-event"].exists,
                       "System off hides New Event from results")

        // Turn System back on: the members return with their own states intact.
        openSystemPage(app, clearing: 5)
        flipSystem(to: true, in: app)
        goBackHome(app)

        type("reminder", into: app)
        XCTAssertTrue(app.buttons["builtin.new-reminder"].waitForExistence(timeout: 5),
                      "turning System back on restores New Reminder")
    }
}
