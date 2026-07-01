import XCTest

/// The UI-only acceptance for File Search (issue #50; CONTEXT.md → File Search;
/// ADR 0015): a filename inside a granted Indexed Folder surfaces as a ranked
/// Result row when the user types it. The matching + ranking logic is covered
/// deterministically by QuickieCore's tests (`FileSearchProvider`, `SearchEngine`,
/// `FilenameIndex`); this proves the app-side wiring around them — the per-folder
/// snapshot builder feeding the `FileSearchProvider` — end to end on a simulator.
///
/// The system document picker can't be driven in CI, so under `--uitesting` the
/// `-uitest-seed-files` argument grants a temporary folder containing a known
/// fixture file at launch (see `IndexedFoldersStore.seedFilesForTestingIfRequested`),
/// exercising the same bookmark → snapshot → match path a picked folder takes.
final class FileSearchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGrantedFilenameSurfacesAsRankedResult() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-uitest-reset-folders", // clean slate, then seed a folder with a file
            "-uitest-seed-files",
        ]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        // Type a prefix of the seeded fixture filename — a strong (prefix) match.
        input.typeText("quickie-fixture-report")

        // A File Search result row is a file Action, whose accessibility identifier
        // is its Core id ("file.<bookmarkID>.<relativePath>"). Its appearance proves
        // the snapshot was built from the granted folder and matched on keystroke.
        let fileRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "file.")
        ).firstMatch
        XCTAssertTrue(fileRow.waitForExistence(timeout: 10),
                      "a granted folder's filename should surface as a File Search result row")
    }
}
