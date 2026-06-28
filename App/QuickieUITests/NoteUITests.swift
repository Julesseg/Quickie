import XCTest

/// The UI-only acceptance criteria for Notes (issue #7) that can only be
/// verified by driving the real app on a simulator: the "New Note" Fallback opens
/// a seeded editor whose saved note persists, surfaces as a searchable Result
/// row, and opens for reading; and the "All Notes" command opens the library list
/// page. The read/compose *logic* (run → .openNote / .composeNote) is covered
/// deterministically by QuickieCore's NoteTests; these prove the SwiftData + UI
/// wiring around it.
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

    /// Type a thought, open the seeded editor via the "New Note" Fallback and
    /// save, then find the note by typing and open it for reading — proving
    /// compose → persist → index → search → open end to end.
    @MainActor
    func testComposeNoteFromInputThenSearchAndOpen() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        // First interaction after launch — allow for a slow cold-launch boot.
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Call the dentist tomorrow"
        input.typeText(thought)

        // The always-present "New Note" Fallback opens the editor seeded with the
        // typed text — title derived from the first line, body the whole text.
        let newNote = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New Note")
        ).firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 5), "the New Note Fallback should always be offered")
        newNote.tap()

        // Seeded editor: the body is pre-filled and Save is ready (title seeded).
        let bodyField = app.textFields["note-body-field"]
        XCTAssertTrue(bodyField.waitForExistence(timeout: 10))
        app.buttons["note-save"].tap()

        // Back at the input (cleared to Home); search by the captured text — the
        // note persisted and surfaces as a ranked Result row.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(thought)

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved note should appear as a searchable result")

        // Its main action opens the note for reading.
        XCTAssertTrue(row.isHittable, "the note result row is an interactive, tappable control")
        row.tap()
        XCTAssertTrue(app.textFields["note-body-field"].waitForExistence(timeout: 5),
                      "opening a note's main action should present it for reading")
    }

    /// The Note library is reached as an "All Notes" result row (not a chrome
    /// button): selecting it opens the list page.
    @MainActor
    func testAllNotesCommandOpensLibrary() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("all notes")

        let allNotes = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "All Notes")
        ).firstMatch
        XCTAssertTrue(allNotes.waitForExistence(timeout: 5), "the All Notes command should surface as a result row")
        allNotes.tap()

        // The Note library list page presents, with its add affordance.
        XCTAssertTrue(app.buttons["note-add"].waitForExistence(timeout: 10),
                      "selecting All Notes should open the Note library list page")
    }
}
