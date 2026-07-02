import XCTest

/// The UI half of instance-level disable (CONTEXT.md → Disabled; issue #68):
/// each row in a provider page's Actions section carries its own enable/disable
/// toggle, deletable actions expose swipe-to-delete, and the permanent
/// built-ins (Save for later / New Snippet) are disable-only. The filtering
/// *logic* — a disabled instance hidden from results/Recents/Favorites, the
/// kind short-circuit — is covered deterministically by QuickieCore's
/// EnablementTests; these prove the row toggle + swipe-to-delete wiring.
final class InstanceDisableUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A fresh in-memory store and a clean signals slate — the reset flag
        // also clears the persisted Disabled set, so a toggle flipped by one
        // test can't leak into the next.
        app.launchArguments = ["--uitesting", "-uitest-reset-signals"]
        app.launch()
        return app
    }

    /// Flips a Form `Toggle` to `on` and asserts it landed. Tapping the
    /// row-spanning switch element's center is a no-op (it misses the control),
    /// so tap the nested switch when the OS exposes one, and fall back to a
    /// trailing-edge coordinate tap — where the control actually sits — when it
    /// doesn't (the same mechanism as AppSettingsUITests).
    @MainActor
    private func flip(_ toggle: XCUIElement, to on: Bool) {
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let landed = NSPredicate(format: "value == %@", on ? "1" : "0")
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3) != .completed {
            // The first mechanism didn't reach the control — try the other one.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "the tap flipped the toggle")
    }

    /// Pops the pushed page back to the launcher via the navigation bar's back
    /// button.
    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    /// Clears the launcher input by backspacing over whatever was typed.
    @MainActor
    private func clearInput(_ app: XCUIApplication, count: Int) {
        let input = app.textFields["search-input"]
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }

    /// Disabling a single Snippet from its row toggle hides it from typed
    /// results while it stays in the Actions list; re-enabling restores it
    /// (issue #68 AC #1) — the whole loop through the real store + engine.
    @MainActor
    func testDisablingASnippetHidesItFromResultsAndReEnablingRestoresIt() throws {
        let app = launchApp()

        // Seed a snippet through the New Snippet Fallback, like a user would.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("Reusable greeting body")

        let newSnippet = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New Snippet")
        ).firstMatch
        XCTAssertTrue(newSnippet.waitForExistence(timeout: 5), "the New Snippet Fallback is always offered")
        newSnippet.tap()

        let title = "Toggle Target"
        let titleField = app.textFields["snippet-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        app.buttons["snippet-save"].tap()

        // Control leg: enabled, the snippet surfaces as a result row.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("toggle")
        let resultRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        XCTAssertTrue(resultRow.waitForExistence(timeout: 5), "an enabled snippet surfaces in results")

        // Open the Snippets page and flip the row's Enabled toggle off. The row
        // must stay in the Actions list — disable hides, it never removes.
        clearInput(app, count: "toggle".count)
        input.typeText("snippets")
        let libraryCommand = app.buttons["builtin.snippets-library"]
        XCTAssertTrue(libraryCommand.waitForExistence(timeout: 5))
        libraryCommand.tap()

        // The toggle's identifier keys off the snippet's stable store id (not
        // its user-editable, collision-prone title), so match by prefix — this
        // test's store holds exactly one snippet.
        let toggle = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "snippet-enabled.")
        ).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "each snippet row carries an Enabled toggle")
        XCTAssertEqual(toggle.value as? String, "1", "a fresh snippet starts enabled")
        flip(toggle, to: false)

        // Hidden from typed results — the always-present Fallbacks prove the
        // result list rendered before the absence is asserted.
        goBackHome(app)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("toggle")
        XCTAssertTrue(newSnippet.waitForExistence(timeout: 5), "results rendered for the query")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch.exists,
            "a disabled snippet is hidden from results"
        )

        // Re-enable from the same row — the reversible half of the verb.
        clearInput(app, count: "toggle".count)
        input.typeText("snippets")
        XCTAssertTrue(libraryCommand.waitForExistence(timeout: 5))
        libraryCommand.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the disabled snippet stays in the Actions list")
        XCTAssertEqual(toggle.value as? String, "0", "the disable persisted")
        flip(toggle, to: true)

        goBackHome(app)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("toggle")
        XCTAssertTrue(resultRow.waitForExistence(timeout: 5), "re-enabling restores the snippet to results")
    }

    /// The Pile provider's Management page (reached from the Settings hub, not
    /// the entries page) lists each entry in its Actions section with an
    /// Enabled toggle and swipe-to-delete (issue #68 AC #1, #2).
    @MainActor
    func testPileProviderPageListsEntriesWithToggleAndSwipeToDelete() throws {
        let app = launchApp()

        // Seed one Pile entry through the silent Save for later capture.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Sort the garage shelves"
        input.typeText(thought)
        let saveForLater = app.buttons["builtin.save-for-later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 5))
        saveForLater.tap()

        // The provider page is reached from the Settings hub's Providers list —
        // distinct from the entries page the "pile" command opens.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("settings")
        let settingsCommand = app.buttons["builtin.settings"]
        XCTAssertTrue(settingsCommand.waitForExistence(timeout: 5))
        settingsCommand.tap()

        let pileRow = app.descendants(matching: .any)["settings-provider-pile"].firstMatch
        XCTAssertTrue(pileRow.waitForExistence(timeout: 10), "the hub lists a Pile provider row")
        var swipes = 5
        while !pileRow.isHittable && swipes > 0 {
            app.swipeUp()
            swipes -= 1
        }
        pileRow.tap()

        // The unified page shape: Options lead, the entries follow as the
        // actions section, each row wearing an Enabled toggle.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "provider-options-pile")
                .firstMatch.waitForExistence(timeout: 10),
            "the Pile provider page leads with its Options section"
        )
        let toggle = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pile-enabled.")
        ).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "each Pile entry row carries an Enabled toggle")
        XCTAssertEqual(toggle.value as? String, "1", "a fresh entry starts enabled")
        flip(toggle, to: false)

        // A Pile entry is deletable, so its row exposes swipe-to-delete —
        // delete destroys, distinct from the reversible toggle above.
        let entryText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(entryText.waitForExistence(timeout: 5), "the actions section lists the entry's text")
        entryText.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "a deletable action exposes swipe-to-delete")
        delete.tap()
        XCTAssertTrue(
            app.staticTexts["The Pile is empty"].waitForExistence(timeout: 5),
            "deleting the only entry empties the actions section"
        )
    }

    /// Disabling an Indexed Folder on the File Search page hides its files from
    /// results while the grant stays listed and revocable (issue #68 follow-up)
    /// — the per-folder counterpart of the per-action toggle.
    @MainActor
    func testDisablingAnIndexedFolderHidesItsFilesFromResults() throws {
        let app = XCUIApplication()
        // A clean folder slate, then a seeded grant holding a known fixture
        // file (the FileSearchUITests seam), plus the usual signal reset.
        app.launchArguments = [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-reset-folders",
            "-uitest-seed-files",
        ]
        app.launch()

        // Control leg: the seeded folder's file surfaces as a ranked result.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let query = "quickie-fixture-report"
        input.typeText(query)
        let fileRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "file.")
        ).firstMatch
        XCTAssertTrue(fileRow.waitForExistence(timeout: 10), "the granted folder's file surfaces in results")

        // Open the File Search page and flip the folder's Enabled toggle off.
        clearInput(app, count: query.count)
        input.typeText("file search")
        let command = app.buttons["builtin.file-search-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()

        let toggle = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "folder-enabled.")
        ).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "each granted folder carries an Enabled toggle")
        XCTAssertEqual(toggle.value as? String, "1", "a fresh grant starts enabled")
        flip(toggle, to: false)

        // Hidden from results — the always-present Fallbacks prove the list
        // rendered before the absence is asserted; the grant itself remains.
        goBackHome(app)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(query)
        let fallback = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New Snippet")
        ).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5), "results rendered for the query")
        XCTAssertFalse(fileRow.exists, "a disabled folder's files are hidden from results")
    }

    /// Permanent built-ins are disable-only (issue #68 AC #2): on the Fallbacks
    /// page a deletable Fallback query exposes swipe-to-delete, while Save for
    /// later refuses the swipe — its only off-switch is the toggle.
    @MainActor
    func testPermanentBuiltInsExposeNoDeleteOnlyDisable() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()

        // Control leg: the seeded web-search Fallback query is deletable.
        let webSearch = app.staticTexts["Search the web"]
        XCTAssertTrue(webSearch.waitForExistence(timeout: 10), "the seeded web-search query is listed")
        webSearch.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "a Fallback query exposes swipe-to-delete")
        delete.tap()

        // Save for later keeps its Enabled toggle but refuses the delete swipe.
        let toggle = app.switches["fallback-enabled.builtin.save-for-later"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Save for later carries an Enabled toggle")
        let saveForLater = app.staticTexts["Save for later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 5))
        saveForLater.swipeLeft()
        XCTAssertFalse(
            app.buttons["Delete"].waitForExistence(timeout: 2),
            "a permanent built-in exposes no swipe-to-delete — disable is its only off-switch"
        )
    }
}
