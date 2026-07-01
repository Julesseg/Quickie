import XCTest

/// The UI-only acceptance criteria for the Pile (issue #62; ADR 0018) that can
/// only be verified by driving the real app on a simulator: "Save for later"
/// captures the typed text **silently** (no editor, no app switch), the saved
/// entry surfaces as a body-text-matched Result row whose tap **stages** it
/// (query replaced, entry consumed), and the "Pile" command opens the page
/// where swipe-to-delete discards without staging. The stage/save *logic*
/// (run → .saveToPile / .stagePileEntry) is covered deterministically by
/// QuickieCore's PileTests; these prove the SwiftData + UI wiring around it.
final class PileUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Start from an empty in-memory store so Pile entries never accumulate
        // across runs — a capture assertion can't pass on a stale row from a
        // previous run.
        app.launchArguments = ["--uitesting"]
        app.launch()
        return app
    }

    /// Type a query, save it for later — silently: no editor appears — then find
    /// the entry by its body text and tap it: the input is replaced with the
    /// saved text (staged) and the entry leaves the Pile (consumed), proving
    /// capture → persist → index → search → stage → consume end to end.
    @MainActor
    func testSaveForLaterThenStageConsumesTheEntry() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        // First interaction after launch — allow for a slow cold-launch boot.
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Call the dentist tomorrow"
        input.typeText(thought)

        // The always-present "Save for later" Fallback drops the text straight
        // into the Pile.
        let saveForLater = app.buttons["builtin.save-for-later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 5),
                      "the Save for later Fallback should always be offered")
        saveForLater.tap()

        // Silent capture: no editor, no confirm — the launcher clears to Home.
        // (The old Note editor's save affordance must never appear.)
        XCTAssertFalse(app.buttons["note-save"].waitForExistence(timeout: 2),
                       "Save for later must not open an editor")
        XCTAssertTrue(input.waitForExistence(timeout: 10))

        // Search by part of the saved text — there is no title; the entry is
        // matched over its body and surfaces as a ranked Result row.
        input.tap()
        input.typeText("dentist")
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the saved entry should appear as a body-text-matched result")

        // Its main action stages it: the entry is consumed — with its full text
        // now the query, no Pile row matches any more; only the Fallbacks serve
        // it…
        row.tap()
        let stale = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: stale)
        waitForExpectations(timeout: 5)

        // …and the input query became the saved text: the user is left "typing"
        // the deferred query.
        XCTAssertEqual(input.value as? String, thought,
                       "staging should replace the input query with the entry's text")
    }

    /// A pre-Pile build's stored notes migrate to titleless Pile entries at
    /// launch (ADR 0018): `-uitest-seed-notes` plants a legacy `StoredNote`
    /// (title ≠ body) before the launch migration runs, and the collapse keeps
    /// the **body** as the entry's searchable text while the **title** is
    /// dropped — it stops matching anything.
    @MainActor
    func testLegacyNotesMigrateToTitlelessPileEntries() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-seed-notes"]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()

        // The dropped title first: once results are up (the always-present
        // fallback row proves that), nothing matches the legacy note's title.
        input.typeText("Groceries list")
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5))
        let byTitle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "oat milk")
        ).firstMatch
        XCTAssertFalse(byTitle.exists,
                       "a migrated entry must not match by the legacy note's dropped title")

        // The surviving body: clear the query and search by the body text — the
        // migrated entry surfaces as a Pile result row.
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        input.typeText("oat milk")
        let byBody = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "buy oat milk and eggs")
        ).firstMatch
        XCTAssertTrue(byBody.waitForExistence(timeout: 5),
                      "a legacy note's body should survive as a searchable Pile entry")
    }

    /// The Pile page is reached as a typed "Pile" command row (not chrome):
    /// it lists every saved entry, and swipe-to-delete discards one without
    /// staging it.
    @MainActor
    func testPileCommandOpensPageAndSwipeDeletes() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Compare ferry times to Nanaimo"
        input.typeText(thought)

        let saveForLater = app.buttons["builtin.save-for-later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 5))
        saveForLater.tap()

        // The "Pile" command surfaces by typing and opens the full-screen page.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("pile")
        let pileCommand = app.buttons["builtin.pile-page"]
        XCTAssertTrue(pileCommand.waitForExistence(timeout: 5),
                      "the Pile command should surface as a result row")
        pileCommand.tap()

        // The page lists the saved entry — the raw text, no title.
        let entry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10),
                      "the Pile page should list the saved entry's text")

        // Swipe-to-delete discards it without staging; the page empties.
        entry.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.staticTexts["The Pile is empty"].waitForExistence(timeout: 5),
                      "deleting the only entry should leave an empty Pile")
    }

    /// Tapping an entry on the Pile page stages it exactly like its result row
    /// (CONTEXT.md → Stage): the page pops back to the launcher, the input
    /// becomes the saved text, and the entry leaves the Pile.
    @MainActor
    func testTappingAnEntryOnThePilePageStagesIt() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Renew the passport before June"
        input.typeText(thought)

        let saveForLater = app.buttons["builtin.save-for-later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 5))
        saveForLater.tap()

        // Open the Pile page via the typed command and tap the entry's row.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("pile")
        let pileCommand = app.buttons["builtin.pile-page"]
        XCTAssertTrue(pileCommand.waitForExistence(timeout: 5))
        pileCommand.tap()

        let entry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()

        // Staged: back on the launcher with the saved text as the live query…
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", thought), evaluatedWith: input)
        waitForExpectations(timeout: 5)

        // …and consumed: reopening the Pile page finds it empty.
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: thought.count + 5))
        input.typeText("pile")
        XCTAssertTrue(pileCommand.waitForExistence(timeout: 5))
        pileCommand.tap()
        XCTAssertTrue(app.staticTexts["The Pile is empty"].waitForExistence(timeout: 10),
                      "a staged entry should have left the Pile")
    }
}
