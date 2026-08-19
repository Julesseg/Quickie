import XCTest

/// The **key command** acceptance for issue #262 (CONTEXT.md → Key command): with
/// a hardware keyboard attached the launcher is fully drivable without touching
/// the screen. The *decisions* — which keys are claimed, and what `esc` unwinds
/// from a given state — are covered deterministically by QuickieCore's
/// `KeyCommandTests`; this proves the app-side wiring end to end on a simulator,
/// the only place a synthesized ⌘-chord can reach a real key binding.
///
/// Every key here is sent with `typeKey(_:modifierFlags:)`, which drives the same
/// HID path a physical keyboard does — so a passing run is evidence the binding
/// actually fired, not that a test seam was called. CI runs this on an **iPhone**
/// simulator, which has no menu bar, so what it exercises is the in-view half of
/// each command (`LauncherKeyShortcuts`); the menu-bar listing itself is iPad-only
/// and verified there by hand.
final class KeyCommandUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // The fresh in-memory store plus a clean signals slate, as everywhere else:
        // persisted Favorites/Frecency from a prior run must not decide which card
        // occupies slot 1.
        app.launchArguments += ["--uitesting", "-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    @MainActor
    private func searchInput(_ app: XCUIApplication) -> XCUIElement {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        return input
    }

    /// The Settings hub's top-level page, recognized by an app-level control that
    /// exists only there and not on any provider panel (the same marker
    /// `AppSettingsUITests` uses).
    @MainActor
    private func settingsHub(_ app: XCUIApplication) -> XCUIElement {
        app.switches["settings-clipboard-prefill"]
    }

    /// AC: ⌘, opens the Settings hub from anywhere at the root.
    @MainActor
    func testCommandCommaOpensTheSettingsHub() throws {
        let app = launchApp()
        _ = searchInput(app)

        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            settingsHub(app).waitForExistence(timeout: 15),
            "⌘, should push the Settings hub"
        )
    }

    /// AC: ⌘1–⌘4 run Favorites 1–4, tap-equivalently to the grid card. The pin is
    /// seeded through the real `SignalsStore.toggleFavorite` path (XCUITest cannot
    /// fire the long-press context menu's action in the simulator — see
    /// `QuickieUITests`), and we pin the always-present built-in Settings row so
    /// the run has an observable outcome: the Settings hub pushes.
    @MainActor
    func testCommandOneRunsTheFirstFavorite() throws {
        let app = launchApp(extraArguments: ["-uitest-pin-favorite", "builtin.settings"])

        XCTAssertTrue(
            app.buttons["favorite.builtin.settings"].waitForExistence(timeout: 15),
            "the seeded pin should occupy the first Favorites-grid slot"
        )

        app.typeKey("1", modifierFlags: .command)

        XCTAssertTrue(
            settingsHub(app).waitForExistence(timeout: 15),
            "⌘1 should run the first Favorite exactly as tapping its card does"
        )
    }

    /// An empty slot resolves to nothing: with a single pin, ⌘4 must be inert —
    /// no run, no crash, and the launcher still on top.
    @MainActor
    func testAnEmptyFavoriteSlotIsInert() throws {
        let app = launchApp(extraArguments: ["-uitest-pin-favorite", "builtin.settings"])

        XCTAssertTrue(app.buttons["favorite.builtin.settings"].waitForExistence(timeout: 15))

        app.typeKey("4", modifierFlags: .command)

        XCTAssertFalse(
            settingsHub(app).waitForExistence(timeout: 5),
            "⌘4 with nothing pinned in slot 4 should do nothing"
        )
        XCTAssertTrue(
            app.buttons["favorite.builtin.settings"].exists,
            "the launcher should still be on top after an inert slot"
        )
    }

    /// AC: ⌘K focuses the search input from anywhere at the root. Focus is
    /// surrendered first via the interactive swipe-dismiss (issue #64), then ⌘K
    /// must reclaim it — proven the same way the rest of the suite proves focus:
    /// text typed *without tapping* lands in the field and filters.
    @MainActor
    func testCommandKRefocusesTheSearchInput() throws {
        let app = launchApp()
        let input = searchInput(app)
        input.tap()
        // A broad query so the list is tall enough for the drag to register as a
        // real scroll-dismiss (the `KeyboardDismissUITests` recipe).
        input.typeText("s")

        let resultRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'builtin.' OR identifier BEGINSWITH 'seed.'")
        )
        XCTAssertTrue(resultRows.firstMatch.waitForExistence(timeout: 10), "the result list rendered")
        // Drag from the Highlighted result row (rank 0) — always rendered just above
        // the input bar, so it stays on-screen however tall the list grows on the
        // small CI runner.
        let highlighted = try XCTUnwrap(
            resultRows.allElementsBoundByIndex.first { $0.isSelected },
            "the Highlighted result row (rank 0) is present and on-screen"
        )
        highlighted.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
            withVelocity: .default,
            thenHoldForDuration: 0.4
        )
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 15),
            "swiping down on the result list surrenders the input's focus"
        )

        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 15),
            "⌘K should bring the input's focus — and the keyboard — back"
        )
        // No tap: with focus reclaimed, typing goes straight into the field.
        app.typeText("ettings")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "typing without tapping after ⌘K should filter, proving the input refocused"
        )
    }

    /// AC: esc clears the query. The launcher lands back on the pre-anything Home
    /// (a clean signals slate leaves nothing pinned or recent), which is the
    /// observable proof the input emptied.
    @MainActor
    func testEscapeClearsTheQuery() throws {
        let app = launchApp()
        let input = searchInput(app)
        input.tap()
        input.typeText("settings")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "typing surfaces the Settings command row"
        )

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "esc should clear the query, returning the launcher to Home"
        )
    }

    /// AC: esc honors the **capture model** — the first clears the step's typed
    /// text, the second abandons the session exactly as the breadcrumb's ×
    /// (`capture-cancel`) does. Driven on the New Reminder breadcrumb through the
    /// `-uitest-stub-reminders` seam: the real capture with only the EventKit edge
    /// stubbed, so no permission dialog blocks the start.
    @MainActor
    func testEscapeClearsTheStepThenAbandonsTheCapture() throws {
        let app = launchApp(extraArguments: ["-uitest-stub-reminders"])
        let input = searchInput(app)
        input.tap()
        input.typeText("reminder")

        let row = app.buttons["builtin.new-reminder"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "typing surfaces the New Reminder row")
        row.tap()

        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(captureField.waitForExistence(timeout: 10), "the breadcrumb starts on the title step")
        captureField.typeText("Buy milk")

        // First esc: the step's text empties, the breadcrumb stays on the same step.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        expectation(
            for: NSPredicate(format: "value == nil OR value == %@ OR value == %@", "", "Title"),
            evaluatedWith: captureField
        )
        waitForExpectations(timeout: 10)
        XCTAssertTrue(captureField.exists, "the first esc clears the step without abandoning the capture")

        // Second esc: the capture is abandoned, exactly as the × affordance does —
        // the breadcrumb goes and the launcher's own input comes back.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(
            captureField.waitForNonExistence(timeout: 10),
            "a second esc should abandon the capture, as the × does"
        )
        XCTAssertTrue(input.waitForExistence(timeout: 10), "abandoning returns the launcher's search input")
    }

    /// AC: esc honors the scoped contexts — the first clears the typed filter and
    /// stays put, the second leaves the Search Files context exactly as its ×
    /// does. Entering the context needs no granted folder: the breadcrumb is the
    /// context, and the filter is what esc is unwinding here.
    @MainActor
    func testEscapeClearsTheFilterThenLeavesTheSearchFilesContext() throws {
        let app = launchApp()
        let input = searchInput(app)
        input.tap()
        input.typeText("search files")

        let commandRow = app.buttons["builtin.search-files"]
        XCTAssertTrue(commandRow.waitForExistence(timeout: 10), "typing surfaces the Search Files command row")
        commandRow.tap()

        let breadcrumb = app.otherElements["file-search-breadcrumb"]
        XCTAssertTrue(breadcrumb.waitForExistence(timeout: 10), "selecting the row enters the scoped context")

        input.typeText("report")

        // First esc: the filter empties, the context stays. The emptied field falls
        // back to the context's own placeholder.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        // An emptied field reports either the empty string or its placeholder,
        // depending on how the platform exposes the accessibility value — accept both.
        let filterCleared = NSPredicate(
            format: "value == nil OR value == %@ OR value == %@", "", "Search files…"
        )
        expectation(for: filterCleared, evaluatedWith: input)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(breadcrumb.exists, "the first esc clears the filter without leaving the context")

        // Second esc — the filter now empty — leaves the context, as the × does.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(
            breadcrumb.waitForNonExistence(timeout: 10),
            "a second esc should leave the Search Files context"
        )
    }
}
