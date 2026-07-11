import XCTest

/// The UI-only acceptance criteria for the **Catalog** Browse page (CONTEXT.md →
/// Catalog; ADR 0028; issue #143) that can only be verified by driving the real app:
/// the "Browse catalog" row on the Custom Actions page pushes the sectioned Catalog
/// page, and per-entry **Install** stamps out a fresh-id Custom Action — so tapping
/// Install twice yields two rows, exactly like hand-creating two identical actions.
///
/// The Catalog's data (every template parses, ≥ 1 slot, schemed) and the fresh-id
/// install semantics are covered deterministically by QuickieCore's CatalogTests;
/// this proves the page + row + store wiring around them.
final class CatalogUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// Opens the Custom Actions page, then pushes the Catalog via the Browse row.
    @MainActor
    private func openCatalog(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("custom actions")

        let command = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'custom actions' surfaces the command row")
        command.tap()

        let browse = app.buttons["browse-catalog"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10), "the Custom Actions page offers a Browse catalog row")
        browse.tap()
    }

    /// Tapping Install on a catalog entry stamps out a Custom Action; a second tap on
    /// the same entry stamps out a *second* row (fresh id every time — ADR 0028).
    @MainActor
    func testInstallCreatesAFreshRowEachTime() throws {
        let app = launchApp()
        openCatalog(app)

        // Google is the first search-engine entry, so it's near the top of the page.
        let install = app.buttons["install-catalog-entry.catalog.google"]
        XCTAssertTrue(install.waitForExistence(timeout: 10), "the Catalog offers a Google entry to install")
        install.tap()
        // The momentary "Added" confirmation disables the button while it shows; it
        // re-enables once the confirmation clears, so wait for that before tapping again.
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        expectEnabled(install, "the Install button re-enables after the Added confirmation")
        install.tap()
        expectEnabled(install, "the Install button re-enables after the second install")

        // Back on the Custom Actions page, two "Google" rows now exist — installing
        // twice minted two independent rows. They sort last (newest), below the seed
        // rows, so scroll to the bottom before counting.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()

        // Match the row title *exactly* — a CONTAINS match would also catch the
        // "Google Maps" seed row. The row renders its title as a static text, so two
        // installs mean two "Google" title labels.
        let googleTitles = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Google"))
        var scrolls = 0
        while googleTitles.count < 2 && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertEqual(googleTitles.count, 2, "installing the same entry twice yields two Custom Action rows")
    }

    /// Polls until an element reports enabled — the "Added" confirmation flips the
    /// Install button disabled for ~1.5s, so a naive re-tap would hit a dead control.
    @MainActor
    private func expectEnabled(_ element: XCUIElement, _ message: String) {
        let deadline = Date().addingTimeInterval(5)
        while !element.isEnabled && Date() < deadline {
            usleep(100_000)
        }
        XCTAssertTrue(element.isEnabled, message)
    }
}
