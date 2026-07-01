import XCTest

/// The UI-only acceptance criteria for Indexed Folder grants (issue #49) that can
/// only be verified by driving the real app on a simulator: a typed "Indexed
/// Folders" command opens the management page, **Add Folder** grants a folder that
/// appears in the list, a grant can be removed, and a grant survives relaunch. The
/// Core additions (the `ManagementPage` case + built-in Action + aliases) are
/// covered deterministically by QuickieCore's tests; these prove the store + page
/// wiring around them.
///
/// The system document picker can't be driven in CI, so under `--uitesting` the
/// Add Folder button grants a real temporary folder directly (see
/// `IndexedFoldersStore.addTemporaryFolderForTesting`) — exercising the same
/// bookmark create → persist → resolve path a picked folder takes.
final class IndexedFolderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        // A clean slate by default; a relaunch passes reset: false to keep the
        // device-local grant file and prove persistence.
        if reset { app.launchArguments.append("-uitest-reset-folders") }
        app.launch()
        return app
    }

    @MainActor
    private func openIndexedFolders(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("folders")

        let command = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Indexed Folders")
        ).firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 5),
                      "the Indexed Folders command should surface as a result row, matchable by 'folders'")
        command.tap()

        XCTAssertTrue(app.buttons["add-indexed-folder"].waitForExistence(timeout: 10),
                      "selecting Indexed Folders should open the management page with an Add Folder button")
    }

    /// The command opens the page; Add Folder grants a folder that appears in the
    /// list; removing it takes it back out — grant → list → revoke end to end.
    @MainActor
    func testAddThenRemoveIndexedFolder() throws {
        let app = launchApp()
        openIndexedFolders(app)

        app.buttons["add-indexed-folder"].tap()

        // The granted folder appears as a row (temp folders are named "Indexed-…").
        let row = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Indexed-")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a granted folder should appear in the list")

        // Swipe to reveal Delete and remove the grant.
        row.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        XCTAssertFalse(row.waitForExistence(timeout: 3), "removing a folder should revoke the grant and drop the row")
    }

    /// A granted folder is persisted as a device-local security-scoped bookmark and
    /// survives relaunch: grant it, terminate, relaunch without the reset flag, and
    /// the row is still there.
    @MainActor
    func testGrantSurvivesRelaunch() throws {
        let app = launchApp()
        openIndexedFolders(app)

        app.buttons["add-indexed-folder"].tap()
        let row = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Indexed-")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a granted folder should appear in the list")

        app.terminate()

        // Relaunch keeping the device-local grant file (no reset flag).
        let relaunched = launchApp(reset: false)
        openIndexedFolders(relaunched)

        let persisted = relaunched.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Indexed-")
        ).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 5),
                      "the grant should survive relaunch — persisted as a security-scoped bookmark")
    }
}
