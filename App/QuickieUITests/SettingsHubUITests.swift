import XCTest

/// The Settings hub's navigation acceptance (ADR 0019; issue #66), verifiable
/// only by driving the real app: a typed provider name deeplinks to that
/// provider's unified page, the top-level hub lists providers and navigates to
/// the very same pages, and the previously row-less dynamic injectors
/// (Calculator, File Search) now have a typed row + page of their own. The
/// routing *logic* (ProviderID, the `.openPage(.settings(panel:))` outcomes)
/// is covered by QuickieCore's SettingsHubTests; these prove the pushes land.
final class SettingsHubUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A clean signals slate, as everywhere else (issue #9): persisted
        // Favorites/Frecency from a prior run must not reorder these results.
        app.launchArguments += ["-uitest-reset-signals"]
        app.launch()
        return app
    }

    /// A provider page is recognized by its Options placeholder row — the
    /// unified two-section shape's lead (issue #66). Queried as `.any` because
    /// SwiftUI may expose the labeled row as a cell, other, or static text
    /// depending on how it merges the accessibility children.
    @MainActor
    private func optionsRow(_ app: XCUIApplication, _ provider: String) -> XCUIElement {
        app.descendants(matching: .any)["provider-options-\(provider)"].firstMatch
    }

    /// Typing a content provider's name and tapping its command row lands on
    /// that provider's unified page under the hub (AC #1): the Quicklinks page
    /// now leads with an Options section above the stored-links list.
    @MainActor
    func testTypingAProviderNameDeeplinksToItsPage() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("quicklinks")

        let row = app.buttons["builtin.quicklinks-page"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'quicklinks' surfaces the Quicklinks command row")
        row.tap()

        XCTAssertTrue(
            optionsRow(app, "quicklinks").waitForExistence(timeout: 10),
            "the Quicklinks command must deeplink to the provider page, which leads with its Options section"
        )
    }

    /// Calculator — a dynamic injector that never had a typed management row —
    /// now surfaces a settings command row that opens its own page (AC #3).
    @MainActor
    func testCalculatorGainsASettingsCommandRowAndPage() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("calculator")

        let row = app.buttons["builtin.calculator-page"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'calculator' surfaces the Calculator settings command row")
        row.tap()

        XCTAssertTrue(
            optionsRow(app, "calculator").waitForExistence(timeout: 10),
            "the Calculator row must open its options-only provider page"
        )
    }

    /// File Search is the second previously row-less injector to gain a typed
    /// settings row + page (AC #3).
    @MainActor
    func testFileSearchGainsASettingsCommandRowAndPage() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("file search")

        let row = app.buttons["builtin.file-search-page"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'file search' surfaces the File Search settings command row")
        row.tap()

        XCTAssertTrue(
            optionsRow(app, "file-search").waitForExistence(timeout: 10),
            "the File Search row must open its options-only provider page"
        )
    }

    /// The top-level Settings page shows the app-level section and the
    /// Providers list, and a provider row opens the same page as its typed
    /// command row (AC #2) — both routes push the same
    /// `.settings(panel:)` destination.
    @MainActor
    func testSettingsHubListsProvidersAndNavigatesToTheSamePage() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("settings")

        let command = app.buttons["builtin.settings"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'settings' surfaces the Settings command row")
        command.tap()

        // The app-level section (issue #65): Appearance is a labeled menu
        // Picker — its options only exist once the menu opens, so assert the
        // picker row itself (element-type-agnostic, as in AppSettingsUITests).
        XCTAssertTrue(
            app.descendants(matching: .any)["appearance-picker"].firstMatch.waitForExistence(timeout: 10),
            "the top-level hub shows the app-level Appearance setting"
        )

        // The Providers section: one navigation row per provider. Calculator
        // sits low in the list and Form rows render lazily, so scroll it into
        // existence before asserting.
        let quicklinksRow = app.descendants(matching: .any)["settings-provider-quicklinks"].firstMatch
        XCTAssertTrue(quicklinksRow.waitForExistence(timeout: 10), "the hub lists a Quicklinks provider row")
        let calculatorRow = app.descendants(matching: .any)["settings-provider-calculator"].firstMatch
        var swipes = 0
        while !calculatorRow.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(calculatorRow.exists, "the hub lists a Calculator provider row")

        // Tapping the row lands on the same unified page the command row opens.
        // Scroll back up so the Quicklinks row is hittable again.
        while !quicklinksRow.isHittable && swipes > 0 {
            app.swipeDown()
            swipes -= 1
        }
        quicklinksRow.tap()
        XCTAssertTrue(
            optionsRow(app, "quicklinks").waitForExistence(timeout: 10),
            "the hub's Quicklinks row must push the same provider page as the typed command"
        )
    }
}
