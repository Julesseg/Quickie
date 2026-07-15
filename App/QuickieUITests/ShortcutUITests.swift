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
/// argument (a comma-delimited name list the store rejoins into the newline
/// payload the URL scheme carries — a launch argument can't hold newlines, the
/// simulator splits them into separate argv entries) — the same "seed the real
/// path" approach the Favorites pin test uses.
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
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// Launches with shortcuts seeded **`acceptsInput` on** (issue #46) so a test can
    /// drive the input-collecting trigger without first flipping toggles by hand.
    @MainActor
    private func launchAppWithInput(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-uitest-reset-signals", "-uitest-seed-input-shortcuts", seed]
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// An imported shortcut surfaces in the Result list, matched by name via the
    /// Indexed Provider — the core "my shortcuts show up and are searchable" slice.
    @MainActor
    func testImportedShortcutIsSearchable() throws {
        let app = launchApp(seed: "Timer,Start Workout,Quickie Sync")

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
    /// imported shortcuts as navigation rows into each shortcut's own settings
    /// page — where the **Enabled** and **Accepts input** toggles live in their
    /// own sections (issue #68 follow-up) — and the Sync Shortcut has
    /// self-filtered itself out of the import.
    @MainActor
    func testShortcutsPageListsImportsWithToggleAndSelfFilters() throws {
        let app = launchApp(seed: "Timer,Start Workout,Quickie Sync")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("shortcuts")

        // Open the Shortcuts management command row (its own page, not nested under
        // Settings) — matched by its stable built-in id.
        let command = app.buttons["builtin.shortcuts-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'shortcuts' surfaces the Shortcuts command")
        command.tap()

        // The page lists each imported shortcut as a navigation row.
        let row = app.buttons["shortcut-row.Start Workout"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "the Shortcuts page lists imported shortcuts as navigation rows"
        )

        // The Sync Shortcut self-filtered itself out — it's not a runnable import.
        XCTAssertFalse(
            app.buttons["shortcut-row.Quickie Sync"].exists,
            "the Sync Shortcut should self-filter out of its own import"
        )

        // Tapping the row pushes the shortcut's own settings page: the Enabled
        // switch and the accepts-input switch, clearly separated in a Form.
        row.tap()
        let enabled = app.switches["shortcut-enabled.Start Workout"]
        XCTAssertTrue(
            enabled.waitForExistence(timeout: 10),
            "the shortcut's page leads with its Enabled toggle"
        )
        // A *seeded* shortcut arrives pre-enabled: the seed hook hands tests
        // surfaced, runnable rows (the state after a user enables their imports).
        // A real URL import starts every new shortcut disabled — that wiring lives
        // in the app root's onOpenURL, which XCUITest can't drive, and the pure
        // added-names split is covered by QuickieCore's ShortcutImportTests.
        XCTAssertEqual(enabled.value as? String, "1", "a seeded shortcut arrives pre-enabled")

        let acceptsInput = app.switches["shortcut-accepts-input.Start Workout"]
        XCTAssertTrue(
            acceptsInput.waitForExistence(timeout: 10),
            "the shortcut's page carries its accepts-input toggle"
        )

        // The toggle is drivable — how Quickie learns a shortcut takes input —
        // via the nested switch control (a Form row's center misses it).
        let control = acceptsInput.switches.firstMatch
        (control.exists ? control : acceptsInput).tap()
        XCTAssertNotEqual(app.state, .notRunning, "toggling accepts-input should not crash the app")
    }

    /// A Shortcut Action with `acceptsInput` **on** runs through the breadcrumb
    /// (issue #46 AC #4): tapping it starts a capture that collects the one optional
    /// `text` input, headed by the shortcut's name — rather than firing immediately.
    /// (The x-callback-url open and the `x-success` reinjection are pure Core logic,
    /// covered by QuickieCore's ShortcutRunTests; XCUITest can neither open the
    /// Shortcuts app nor deliver the inbound `quickie://` callback.)
    @MainActor
    func testInputAcceptingShortcutCollectsInputThroughBreadcrumb() throws {
        let app = launchAppWithInput(seed: "Translate")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("translate")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Translate")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the input-accepting shortcut surfaces as a row")
        row.tap()

        // The capture's bottom input field is the reliable "a breadcrumb is in flight"
        // signal — the top breadcrumb bar (its cancel × and crumbs) rides under a
        // progressive blur / status-bar bleed and is flaky to query. The field's mere
        // presence proves the input-accepting shortcut collects text through the
        // breadcrumb rather than firing immediately (a no-input shortcut shows none).
        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(
            captureField.waitForExistence(timeout: 5),
            "an input-accepting shortcut starts the breadcrumb rather than firing immediately"
        )
    }

    /// The input Argument is **optional** (issue #46): a user with nothing to type
    /// can submit the step empty and the shortcut still runs, rather than being
    /// trapped in the breadcrumb. Pressing Return on the empty capture field completes
    /// the capture (fires the shortcut and dismisses the breadcrumb) — the escape the
    /// generic `commitText` empty-guard would otherwise deny.
    @MainActor
    func testInputAcceptingShortcutCanRunWithEmptyInput() throws {
        let app = launchAppWithInput(seed: "Translate")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("translate")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Translate")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The capture field auto-focuses; submit it empty via Return.
        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(captureField.waitForExistence(timeout: 5), "the input breadcrumb starts")
        captureField.tap()
        captureField.typeText("\n")

        // The capture completes (fires the shortcut with no input) rather than the
        // empty submit silently no-opping — the input field is gone, not stuck. Keyed
        // off `capture-input` (the reliable bottom field), not the flaky top-bar ×.
        XCTAssertTrue(
            captureField.waitForNonExistence(timeout: 5),
            "submitting the optional input empty should run the shortcut, not trap the user"
        )
    }

    /// An accepts-input Shortcut promoted to a fallback runs in **one tap** (issue
    /// #114): its free-text input makes it fallback-eligible, so activating it on the
    /// Fallbacks page and selecting its fallback row seeds-and-commits the typed query
    /// as the shortcut's input and fires it immediately — a single-argument fallback
    /// takes no breadcrumb stop. (The x-callback-url open is pure Core logic; the
    /// reliable UI signal is that no input breadcrumb traps the user.)
    @MainActor
    func testInputAcceptingShortcutRunsAsOneTapFallback() throws {
        let app = launchAppWithInput(seed: "Translate")

        // Activate Translate on the Fallbacks page.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()

        // Find the Translate row in the Available pool by title and tap its promote
        // plus *within that row* — the same cell-scoped pattern the Custom Action
        // activation uses, which resolves reliably where a top-level button-id query
        // over a lazy List row does not.
        let poolCell = app.cells.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Translate")
        ).firstMatch
        var scrolls = 0
        while !poolCell.exists && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(poolCell.waitForExistence(timeout: 10),
                      "the accepts-input shortcut waits in the fallback pool")
        let promote = poolCell.buttons["Add to active fallbacks"]
        XCTAssertTrue(promote.waitForExistence(timeout: 5), "the pool row offers a promote button")
        promote.tap()

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()

        // Type a query and pick the promoted shortcut's fallback row.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("hola mundo")
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Translate")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the promoted shortcut rides the fallback region")
        row.tap()

        // Seed-and-commit fires it in one tap: no input breadcrumb traps the user
        // (a single-argument fallback completes immediately, unlike a verb-first tap
        // which would open the breadcrumb to collect the input).
        XCTAssertTrue(
            app.textFields["capture-input"].waitForNonExistence(timeout: 5),
            "a single-argument shortcut fallback runs in one tap — no breadcrumb stop"
        )
    }

    /// A Shortcut Action with `acceptsInput` **off** fires immediately (issue #46 AC
    /// #1): tapping it hands off via x-callback-url with no input — it must not start
    /// the input breadcrumb. The hand-off leaves the app (or no-ops in a simulator
    /// without the Shortcuts app), but the launcher must never enter a capture.
    @MainActor
    func testShortcutWithoutInputDoesNotCollectInput() throws {
        let app = launchApp(seed: "Timer")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("timer")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Timer")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the shortcut surfaces as a row")
        row.tap()

        // No breadcrumb: a no-input shortcut fires straight away — no capture input
        // field appears (keyed off the reliable bottom field, not the top-bar ×).
        XCTAssertFalse(
            app.textFields["capture-input"].waitForExistence(timeout: 3),
            "a shortcut with input off should fire immediately, not open the input breadcrumb"
        )
    }
}
