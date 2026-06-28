import XCTest

/// The UI-only acceptance criteria for Notes (issue #7) that can only be
/// verified by driving the real app on a simulator: the instant "New Note"
/// capture turns the typed text into a stored Note with no app switch, and a
/// note created in the library persists, surfaces as a searchable Result row,
/// and its main action opens it for reading. The read/capture *logic*
/// (run → .openNote / .createNote) is covered deterministically by QuickieCore's
/// NoteTests; these prove the SwiftData + UI wiring around it.
final class NoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Start from an empty in-memory store so notes never accumulate across
        // runs — without this a capture assertion could pass on a stale row from
        // a previous run.
        app.launchArguments = ["--uitesting"]
        app.launch()
        return app
    }

    /// Type a thought, run the "New Note" capture from the Result list, then find
    /// it in the Note library — proving capture → persist → list end to end with
    /// no app switch.
    @MainActor
    func testNewNoteCaptureFromInput() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        // First interaction after launch — allow for a slow cold-launch boot.
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Call the dentist tomorrow"
        input.typeText(thought)

        // The always-present "New Note" Fallback rides the bottom of the list,
        // labelled "New Note"; running it captures the typed text.
        let capture = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New Note")
        ).firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 5), "the New Note capture should always be offered")
        capture.tap()
        XCTAssertNotEqual(app.state, .notRunning, "capturing a note should not crash the app")

        // Open the Note library; the captured note persisted and is listed,
        // titled by its first line.
        app.buttons["open-notes"].tap()
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the captured note should persist and appear in the library")
    }

    /// Create a note through the library editor, then find it by typing and run
    /// it — proving create → persist → index → search → open end to end.
    @MainActor
    func testCreateNoteThenSearchAndOpen() throws {
        let app = launchApp()

        // Open the Note library and compose a new note. Wait for the button
        // before tapping: this is the first interaction after launch, and on a
        // cold-launched simulator tapping before the app is ready drops the tap
        // and the sheet never presents.
        let openNotes = app.buttons["open-notes"]
        XCTAssertTrue(openNotes.waitForExistence(timeout: 30))
        openNotes.tap()
        XCTAssertTrue(app.buttons["note-add"].waitForExistence(timeout: 10))
        app.buttons["note-add"].tap()

        let title = "Quickie Roadmap"
        let titleField = app.textFields["note-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)

        let bodyField = app.textFields["note-body-field"]
        XCTAssertTrue(bodyField.waitForExistence(timeout: 10))
        bodyField.tap()
        bodyField.typeText("Ship the notes provider")

        app.buttons["note-save"].tap()

        // Back in the library, dismiss to the input.
        app.buttons["Done"].tap()

        // Type to search — the note surfaces as a ranked Result row.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("roadmap")

        // A result row is a Button whose label is the note title; its identifier
        // is a store-derived hash, so match on the label (mirroring the snippet
        // tests, which find rows by the button rather than the merged inner Text).
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved note should appear as a searchable result")

        // Its main action opens the note for reading — assert the row is hittable
        // and the open path is wired without crashing. The read outcome
        // (run → .openNote(id:)) is covered deterministically by NoteTests.
        XCTAssertTrue(row.isHittable, "the note result row is an interactive, tappable control")
        row.tap()
        XCTAssertTrue(app.textFields["note-body-field"].waitForExistence(timeout: 5),
                      "opening a note's main action should present it for reading")
    }
}
