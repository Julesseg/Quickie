import XCTest

/// The UI-only acceptance for the **Pending query** (issue #152; ADR 0031):
/// unresolved input left at background time is restored on a quick return,
/// committed to the Pile after the 30-second window, and committed immediately
/// by any Entry surface — replacing the old silent discard. The restore/commit
/// decision itself (qualification, the window, the entry-surface rule) is
/// covered deterministically by QuickieCore's PendingQueryTests; these prove
/// the app-side wiring: snapshot → App Group → activation resolution → input /
/// Pile / flash.
///
/// XCUITest cannot control the wall clock across a backgrounding, so the two
/// cold-launch paths ride the `-uitest-seed-pending <text>` +
/// `-uitest-pending-age <seconds>` seam, which plants a *real* snapshot through
/// `PendingQueryStore.save` before `RootView` resolves it — the same
/// "drive the real path" approach as the widget-run and deeplink seams. The
/// entry-surface commit is driven warm through the `-uitest-entry` trigger.
final class PendingQueryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // The reset clears the App Group snapshot key too, so a prior run's
        // pending query can never restore or commit into this launch.
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-instant-motion",
        ] + extraArguments
        app.launch()
        return app
    }

    /// Opens the Pile entries page and asserts `text` is (or is not) listed.
    @MainActor
    private func assertPile(lists text: String, _ shouldList: Bool, in app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("pile")
        let pileCommand = app.buttons["builtin.pile-page"]
        XCTAssertTrue(pileCommand.waitForExistence(timeout: 5), "the Pile command should surface as a result row")
        pileCommand.tap()

        let entry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", text)
        ).firstMatch
        if shouldList {
            XCTAssertTrue(entry.waitForExistence(timeout: 10),
                          "the Pile page should list the committed pending query")
        } else {
            XCTAssertFalse(entry.waitForExistence(timeout: 3),
                           "the Pile page must not list the text")
        }
    }

    /// A cold launch within the window restores the pending query into the
    /// input — the path that makes a quick return survive termination (the
    /// issue's "now survives termination too").
    @MainActor
    func testColdLaunchWithinWindowRestoresQuery() throws {
        let thought = "compare ferry times"
        let app = launchApp(extraArguments: [
            "-uitest-seed-pending", thought,
            "-uitest-pending-age", "5",
        ])

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        // The restore lands the user mid-thought: the text is back in the input
        // and the matcher re-ran — the always-present fallback row proves the
        // restored text is live, not just displayed.
        expectation(for: NSPredicate(format: "value == %@", thought), evaluatedWith: input)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "the restored query should drive live results")
    }

    /// A cold launch past the window commits the pending query: clean Home, a
    /// Pile entry with the exact text — nothing silently destroyed.
    @MainActor
    func testColdLaunchPastWindowCommitsToPile() throws {
        let thought = "book the campsite"
        let app = launchApp(extraArguments: [
            "-uitest-seed-pending", thought,
            "-uitest-pending-age", "60",
        ])

        // Clean Home: the input is empty (the empty-query placeholder shows).
        XCTAssertTrue(app.staticTexts["home-placeholder"].waitForExistence(timeout: 30),
                      "an expired pending query should land on a clean Home")

        // The text landed in the Pile, exact and whole.
        assertPile(lists: thought, true, in: app)
    }

    /// An Entry surface commits the pending query immediately, at any age —
    /// replacing today's silent discard. Driven warm: type a query, fire the
    /// `quickie://entry` reset through its real dispatch path, then find the
    /// text saved in the Pile.
    @MainActor
    func testEntrySurfaceCommitsTypedQueryToPile() throws {
        let thought = "renew the passport"
        let app = launchApp(extraArguments: ["-uitest-entry"])

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText(thought)
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "typing surfaces results, so there is an unresolved query to commit")

        let trigger = app.buttons["uitest-entry-trigger"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "the -uitest-entry seam should arm its trigger")
        trigger.tap()

        // The reset still lands on a clean, focused Home…
        XCTAssertTrue(app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
                      "the entry reset should clear the query back to a clean Home")

        // …but the text was committed, not discarded.
        assertPile(lists: thought, true, in: app)
    }

    /// The Pile provider's Management page declares the auto-save toggle from
    /// its schema (ADR 0020), default on. Read-only: flipping is generic
    /// renderer behavior covered by SchemaOptionsUITests, and the off-state
    /// logic (snapshot nothing) is Core-covered.
    @MainActor
    func testPileSettingsPageShowsAutoSaveToggleDefaultOn() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("pile settings")
        let command = app.buttons["builtin.pile-settings"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing surfaces the Pile settings command row")
        command.tap()

        let toggle = app.switches["setting-pile.autoSave"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the Pile page should render the schema-declared auto-save toggle")
        XCTAssertEqual(toggle.value as? String, "1", "the auto-save toggle defaults to on")
    }
}
