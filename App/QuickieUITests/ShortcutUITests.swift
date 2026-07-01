import XCTest

/// The UI-only acceptance criteria for imported Shortcut Actions (issue #45) that
/// can only be verified by driving the real app on a simulator: shortcuts brought
/// in by the Sync Shortcut import surface as searchable Result rows, and the
/// dedicated Shortcuts management page lists them with a per-row "accepts input"
/// toggle. The parse/dedup/self-filter and re-sync reconciliation *logic* is
/// covered deterministically by QuickieCore's ShortcutImportTests; these prove the
/// store + provider + page wiring around it.
///
/// XCUITest can't deliver a `quickie://import` URL to the app, so the import is
/// seeded through the *real* ingest path via the `-uitest-seed-shortcuts` launch
/// argument (a newline-delimited payload, exactly what the URL scheme carries) —
/// the same "seed the real path" approach the Favorites pin test uses.
final class ShortcutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Clean in-memory + signals slate so nothing leaks across runs, then seed
        // the imported shortcuts through the real parse→reconcile→persist path.
        app.launchArguments += ["--uitesting", "-uitest-reset-signals", "-uitest-seed-shortcuts", seed]
        app.launch()
        return app
    }

    /// An imported shortcut surfaces in the Result list, matched by name via the
    /// Indexed Provider — the core "my shortcuts show up and are searchable" slice.
    @MainActor
    func testImportedShortcutIsSearchable() throws {
        let app = launchApp(seed: "Timer\nStart Workout\nQuickie Sync")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("workout")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Start Workout")
        ).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "an imported shortcut should surface as a searchable result row"
        )
    }

    /// The dedicated Shortcuts page (typed "shortcuts", not under Settings) lists
    /// imported shortcuts with a per-row "accepts input" toggle, and the Sync
    /// Shortcut has self-filtered itself out of the import.
    @MainActor
    func testShortcutsPageListsImportsWithToggleAndSelfFilters() throws {
        let app = launchApp(seed: "Timer\nStart Workout\nQuickie Sync")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("shortcuts")

        // Open the Shortcuts management command row (its own page, not nested under
        // Settings) — matched by its stable built-in id.
        let command = app.buttons["builtin.shortcuts-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'shortcuts' surfaces the Shortcuts command")
        command.tap()

        // The page lists each imported shortcut with an "accepts input" toggle.
        let toggle = app.switches["shortcut-accepts-input.Start Workout"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "the Shortcuts page lists imported shortcuts with a per-row accepts-input toggle"
        )

        // The Sync Shortcut self-filtered itself out — it's not a runnable import.
        XCTAssertFalse(
            app.switches["shortcut-accepts-input.Quickie Sync"].exists,
            "the Sync Shortcut should self-filter out of its own import"
        )

        // The toggle is drivable (a real List Toggle, not a context menu) and
        // flipping it — how Quickie learns a shortcut takes input — doesn't crash.
        toggle.tap()
        XCTAssertNotEqual(app.state, .notRunning, "toggling accepts-input should not crash the app")
    }
}
