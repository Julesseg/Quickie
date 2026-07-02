import XCTest

/// The user-facing File Search acceptance for issue #51 (CONTEXT.md → Search Files
/// context, File Search; ADRs 0014 & 0015): the two surfacing paths and opening.
/// The matching/ranking and the context filter are covered deterministically by
/// QuickieCore's tests (`FileSearchProvider`, `SearchEngine`); this proves the
/// app-side wiring end to end on a simulator — the only place XCUITest can run.
///
/// As in `FileSearchUITests`, the system document picker can't be driven in CI, so
/// `-uitest-seed-files` grants a temporary folder holding a known fixture file at
/// launch (see `IndexedFoldersStore.seedFilesForTestingIfRequested`), exercising the
/// real bookmark → snapshot → match → open path a picked folder would take.
final class SearchFilesContextUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-uitest-reset-folders", // clean slate, then seed a folder with a file
            "-uitest-seed-files",
        ]
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// AC: a "Search Files" command row enters a scoped, uncapped, full-height
    /// file-search context shown as a `[Search Files] ▸ …` breadcrumb; dismissing it
    /// returns to normal results. Entering is by row selection only — no mode toggle.
    @MainActor
    func testSearchFilesRowEntersScopedContextAndDismisses() throws {
        let app = launchedApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()

        // Typing surfaces the built-in "Search Files" command row like any other.
        input.typeText("search files")
        let commandRow = app.buttons["builtin.search-files"]
        XCTAssertTrue(commandRow.waitForExistence(timeout: 10),
                      "typing should surface the Search Files command row")

        // Selecting the row — never a chrome toggle — enters the scoped context.
        commandRow.tap()
        let breadcrumb = app.otherElements["file-search-breadcrumb"]
        XCTAssertTrue(breadcrumb.waitForExistence(timeout: 10),
                      "selecting Search Files should show the [Search Files] breadcrumb")

        // Every keystroke now filters only filenames: the seeded fixture surfaces.
        input.typeText("report")
        let fileRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "file.")
        ).firstMatch
        XCTAssertTrue(fileRow.waitForExistence(timeout: 10),
                      "the scoped filter should surface the granted folder's file")

        // Dismissing the context returns to normal results.
        app.buttons["file-search-cancel"].tap()
        XCTAssertFalse(breadcrumb.waitForExistence(timeout: 5),
                       "dismissing the context should remove the breadcrumb")
    }

    /// AC: a file row's main action opens the file in QuickLook, resolving the
    /// bookmark + relative path under a start/stop access bracket. Exercised via the
    /// inline surfacing path (typing a strong filename prefix).
    @MainActor
    func testOpeningFileRowPresentsQuickLook() throws {
        let app = launchedApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        // A strong prefix of the seeded fixture filename surfaces it inline.
        input.typeText("quickie-fixture-report")

        let fileRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "file.")
        ).firstMatch
        XCTAssertTrue(fileRow.waitForExistence(timeout: 10),
                      "the fixture filename should surface as an inline file row")

        // Its main action opens QuickLook. Assert on our wrapper's identifier, or
        // QuickLook's own Done affordance as a fallback (its chrome is localized and
        // versioned, so we don't hard-code its labels).
        fileRow.tap()
        let quickLook = app.otherElements["file-quicklook"]
        let done = app.buttons["Done"]
        XCTAssertTrue(quickLook.waitForExistence(timeout: 10) || done.waitForExistence(timeout: 10),
                      "tapping a file row should open the file in QuickLook")
    }
}
