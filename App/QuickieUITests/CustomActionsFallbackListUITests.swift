import XCTest

/// Acceptance coverage for the Custom Actions page's complete Fallback-list home
/// (ADR 0045; issue #300). The Core suite pins tier membership and ordering; these
/// tests drive the page's public controls and destinations on the app's two CI device
/// families.
final class CustomActionsFallbackListUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(shortcuts: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-stub-reminders",
            "-uitest-instant-motion",
        ]
        if let shortcuts {
            app.launchArguments += ["-uitest-seed-input-shortcuts", shortcuts]
        }
        app.launch()
        return app
    }

    @MainActor
    private func openCustomActions(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("custom actions")
        let command = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()
        XCTAssertTrue(app.navigationBars["Custom Actions"].waitForExistence(timeout: 10))
    }

    /// The former Fallbacks routes now resolve to the Custom Actions command, whose
    /// page hosts the fallback list. No second command row or navigation surface is
    /// left behind for the retired provider.
    @MainActor
    func testFallbackAliasesOpenCustomActionsWithoutAFallbacksRow() throws {
        for query in ["fallback", "fallbacks", "search engines", "manage fallbacks"] {
            let app = launchApp()
            let input = app.textFields["search-input"]
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            input.typeText(query)

            let customActions = app.buttons["builtin.custom-actions-page"]
            XCTAssertTrue(customActions.waitForExistence(timeout: 5), "\(query) surfaces Custom Actions")
            XCTAssertFalse(app.buttons["builtin.fallbacks-page"].exists, "\(query) has no Fallbacks row")
            customActions.tap()
            XCTAssertTrue(app.navigationBars["Custom Actions"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    /// Resolve a row by its visible title, walking a short phone-sized list in both
    /// directions so a promotion that moves it up the ladder stays discoverable.
    @MainActor
    private func cell(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        for _ in 0..<4 where !cell.exists { app.swipeDown() }
        for _ in 0..<6 where !cell.exists { app.swipeUp() }
        return cell
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.exists { app.swipeUp() }
    }

    @MainActor
    private func addAction(_ app: XCUIApplication, name: String, url: String) {
        let add = app.buttons["add-custom-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let nameField = app.textFields["custom-action-name-field"]
        let urlField = app.textFields["custom-action-url-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        urlField.tap()
        urlField.typeText(url)
        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func addDateFirstAction(_ app: XCUIApplication, name: String, url: String, token: String) {
        let add = app.buttons["add-custom-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let nameField = app.textFields["custom-action-name-field"]
        let urlField = app.textFields["custom-action-url-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        urlField.tap()
        urlField.typeText(url)

        let picker = app.descendants(matching: .any)
            .matching(identifier: "custom-action-type.\(token)").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        if app.buttons["Date"].waitForExistence(timeout: 3) {
            app.buttons["Date"].tap()
        } else {
            XCTAssertTrue(app.menuItems["Date"].waitForExistence(timeout: 3))
            app.menuItems["Date"].tap()
        }

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5))
    }

    /// The page retains its complete shape: its three fallback tiers stay visible
    /// even when empty, and a static Custom Action lands in Other rather than any
    /// fallback rung.
    @MainActor
    func testPageShowsFallbackTiersAndKeepsStaticActionsInOther() throws {
        let app = launchApp()
        openCustomActions(app)

        XCTAssertTrue(app.staticTexts["Options"].exists)
        XCTAssertTrue(app.switches["provider-enabled-custom-actions"].exists)
        XCTAssertTrue(app.switches["setting-custom-actions.fallbacks"].exists)
        XCTAssertTrue(app.buttons["browse-catalog"].exists,
                      "Browse catalog stays inside the leading Options section")
        XCTAssertTrue(app.staticTexts["Shelf"].exists)
        XCTAssertTrue(app.staticTexts["Active fallbacks"].exists)
        reveal(app.staticTexts["Top is most important — nearest the input in results."], in: app)
        XCTAssertTrue(app.staticTexts["Top is most important — nearest the input in results."].exists)
        reveal(app.staticTexts["Available for fallback"], in: app)
        XCTAssertTrue(app.staticTexts["Available for fallback"].exists)
        reveal(app.staticTexts["Other actions"], in: app)
        XCTAssertTrue(app.staticTexts["Other actions"].exists)
        XCTAssertTrue(app.staticTexts["A fallback takes what you typed as its first argument."].exists)

        addAction(app, name: "Static documentation", url: "https://example.com/docs")
        let staticAction = cell(app, titled: "Static documentation")
        XCTAssertTrue(staticAction.waitForExistence(timeout: 10))
        XCTAssertTrue(staticAction.switches.firstMatch.exists,
                      "Other actions carry their instance Enabled toggle")
        XCTAssertFalse(staticAction.buttons["Add to active fallbacks"].exists,
                      "a static Custom Action is never offered as a fallback")
    }

    /// Other actions contains precisely non-fallback Custom Actions, sorted by title:
    /// a slot-less static link and a date-first template belong there, while the
    /// fallback captures and input Shortcut remain in the three ladder sections.
    @MainActor
    func testOtherActionsContainsOnlyNonFallbackCustomActionsInTitleOrder() throws {
        let app = launchApp(shortcuts: "Timer")
        openCustomActions(app)

        addAction(app, name: "Zulu static", url: "https://example.com/zulu")
        addDateFirstAction(
            app,
            name: "Alpha dated",
            url: "calendar://event?when={when}",
            token: "when"
        )

        let alpha = cell(app, titled: "Alpha dated")
        let zulu = cell(app, titled: "Zulu static")
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        XCTAssertTrue(zulu.waitForExistence(timeout: 10))
        XCTAssertLessThan(alpha.frame.minY, zulu.frame.minY,
                          "Other actions sorts its Custom Actions alphabetically by title")
        XCTAssertFalse(alpha.buttons["Add to active fallbacks"].exists,
                       "a date-first template is not fallback eligible")
        XCTAssertFalse(zulu.buttons["Add to active fallbacks"].exists,
                       "a static link is not fallback eligible")
        XCTAssertFalse(app.otherElements["custom-actions-row.other.builtin.new-reminder"].exists)
        XCTAssertFalse(app.otherElements["custom-actions-row.other.builtin.new-event"].exists)
        XCTAssertFalse(app.otherElements["custom-actions-row.other.builtin.save-for-later"].exists)
        XCTAssertFalse(app.otherElements["custom-actions-row.other.builtin.new-snippet"].exists)
        XCTAssertFalse(app.otherElements["custom-actions-row.other.shortcut.timer"].exists,
                       "capture actions and input Shortcuts remain in fallback sections")
    }

    /// The page wires the existing Core tier operations through the merged surface:
    /// a pool promotion becomes an Active row, whose red minus returns it to the pool.
    @MainActor
    func testPromotingAndDemotingFromTheMergedPageUsesTheTwoTiers() throws {
        let app = launchApp()
        openCustomActions(app)

        let reminder = cell(app, titled: "New Reminder")
        XCTAssertTrue(reminder.waitForExistence(timeout: 10))
        let promote = reminder.buttons["Add to active fallbacks"]
        XCTAssertTrue(promote.waitForExistence(timeout: 5))
        promote.tap()

        let active = cell(app, titled: "New Reminder")
        let demote = active.buttons["Remove from active fallbacks"]
        XCTAssertTrue(demote.waitForExistence(timeout: 5))
        demote.tap()
        XCTAssertTrue(cell(app, titled: "New Reminder").buttons["Add to active fallbacks"].waitForExistence(timeout: 5))
    }

    /// Every fallback row routes to the home that owns it: Custom Action editor,
    /// imported Shortcut settings, and the four built-in capture provider pages.
    @MainActor
    func testFallbackRowsOpenTheirOwningEditorsAndProviderPages() throws {
        let app = launchApp(shortcuts: "Timer")
        openCustomActions(app)

        addAction(app, name: "Search notes", url: "notes:///search?query={query}")
        let custom = cell(app, titled: "Search notes")
        XCTAssertTrue(custom.waitForExistence(timeout: 10))
        custom.tap()
        XCTAssertTrue(app.textFields["custom-action-name-field"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        let shortcut = cell(app, titled: "Timer")
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        shortcut.tap()
        XCTAssertTrue(app.switches["shortcut-enabled.Timer"].waitForExistence(timeout: 10))
        app.navigationBars["Timer"].buttons.firstMatch.tap()

        assertProviderDestination(app, row: "New Reminder", title: "Reminders")
        assertProviderDestination(app, row: "New Event", title: "Events")
        assertProviderDestination(app, row: "Save for later", title: "Pile")
        assertProviderDestination(app, row: "New Snippet", title: "Snippets")
    }

    @MainActor
    private func assertProviderDestination(_ app: XCUIApplication, row: String, title: String) {
        let fallback = cell(app, titled: row)
        XCTAssertTrue(fallback.waitForExistence(timeout: 10), "\(row) is a fallback row")
        fallback.tap()
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "\(row) opens the \(title) management page")
        bar.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Custom Actions"].waitForExistence(timeout: 10))
    }
}
