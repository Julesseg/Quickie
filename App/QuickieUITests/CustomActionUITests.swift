import XCTest

/// The UI-only acceptance criteria for the Custom Actions authoring surface
/// (CONTEXT.md → Custom Action; ADR 0021, issue #94) that can only be verified by
/// driving the real app on a simulator: the **live-mirroring editor** (typing the
/// URL grows argument rows, renaming a row rewrites the URL token, drag sets the
/// fill order, the fallback toggle gates on a slot, and Save is gated), and one
/// **end-to-end** breadcrumb run of a multi-argument Custom Action authored through
/// the new Management page.
///
/// The reconciliation, rename, reorder, and validation *logic* are covered
/// deterministically by QuickieCore's CustomActionEditorTests; these prove the
/// store + editor + engine + capture wiring around them. Like the Shortcut tests,
/// the actual URL open leaves the app (or no-ops in a simulator without the target
/// app), so the reliable end-of-run signal is the breadcrumb dismissing — the
/// capture completed rather than trapping the user mid-slot.
final class CustomActionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A fresh in-memory store and clean signals slate, plus instant motion so
        // the capture transitions don't add flake to the breadcrumb assertions.
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// Opens the Custom Actions Management page by typing its name and tapping the
    /// command row — the same typed route a user reaches it through.
    @MainActor
    private func openCustomActionsPage(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("custom actions")

        let command = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'custom actions' surfaces the command row")
        command.tap()
    }

    /// Opens the editor for a brand-new Custom Action via the page's Add button.
    @MainActor
    private func openNewEditor(_ app: XCUIApplication) {
        let add = app.buttons["add-custom-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the Custom Actions page offers an Add button")
        add.tap()
        XCTAssertTrue(app.textFields["custom-action-name-field"].waitForExistence(timeout: 5),
                      "the editor sheet has a name field")
    }

    /// Types into a field, first clearing whatever it already holds.
    @MainActor
    private func setText(_ text: String, in field: XCUIElement) {
        field.tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    /// Pops the pushed page back to the launcher.
    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    // MARK: - Editor: live slot detection + rename rewrites the token

    /// Typing the URL grows an argument row per `{name}` slot, deleting a token drops
    /// its row immediately (hard mirror), and renaming a row rewrites the URL token —
    /// the whole point of the live-mirroring editor (ADR 0021).
    @MainActor
    func testEditorLiveMirrorsSlotsAndRenameRewritesToken() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        let urlField = app.textFields["custom-action-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))

        // Two slots typed → two argument rows appear, mirroring the template.
        setText("things:///add?title={title}&notes={notes}", in: urlField)
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5),
                      "the {title} slot mirrors an argument row")
        XCTAssertTrue(app.textFields["custom-action-arg.notes"].exists,
                      "the {notes} slot mirrors an argument row")

        // Delete the {notes} token from the URL → its row drops immediately.
        setText("things:///add?title={title}", in: urlField)
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["custom-action-arg.notes"].exists,
                       "deleting the token drops its row — no stashing")

        // A numeric slot auto-labels; renaming its row rewrites the URL token.
        setText("app://x?a={1}", in: urlField)
        let numericRow = app.textFields["custom-action-arg.1"]
        XCTAssertTrue(numericRow.waitForExistence(timeout: 5), "a numeric {1} slot appears as a row")
        numericRow.tap()
        numericRow.typeText("title\n")

        // The token in the URL is rewritten in place, and the row now keys off the
        // chosen name.
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5),
                      "renaming the row rewrites the URL token")
        let url = app.textFields["custom-action-url-field"].value as? String ?? ""
        XCTAssertTrue(url.contains("{title}"), "the URL token was rewritten to {title} (was: \(url))")
        XCTAssertFalse(url.contains("{1}"), "the old numeric token is gone (was: \(url))")
    }

    // MARK: - Editor: Save gating + slot-less Quicklink redirect

    /// Save is gated on a valid definition, and a slot-less URL is redirected toward
    /// Quicklinks rather than saved (ADR 0021).
    @MainActor
    func testSaveIsGatedAndSlotlessURLRedirectsToQuicklinks() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save is disabled with an empty name and no URL")

        // A slot-less URL: the redirect hint shows, and Save stays disabled.
        setText("Docs", in: app.textFields["custom-action-name-field"])
        setText("https://example.com", in: app.textFields["custom-action-url-field"])
        XCTAssertTrue(app.staticTexts["custom-action-quicklink-redirect"].waitForExistence(timeout: 5),
                      "a slot-less URL is gently redirected toward Quicklinks")
        XCTAssertFalse(save.isEnabled, "a slot-less URL can't be saved as a Custom Action")

        // Add a slot → the definition validates and Save enables.
        setText("https://example.com/search?q={q}", in: app.textFields["custom-action-url-field"])
        XCTAssertTrue(app.textFields["custom-action-arg.q"].waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "a named, slotted, schemed URL validates for Save")
    }

    // MARK: - Editor: fallback toggle gating

    /// The fallback toggle appears only once the URL carries a slot (its first
    /// argument is what a fallback seeds) — with no slot there is nothing to gate on,
    /// so the toggle isn't offered (ADR 0021).
    @MainActor
    func testFallbackToggleAppearsOnlyWithASlot() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        // No slot yet → no fallback toggle.
        setText("https://example.com", in: app.textFields["custom-action-url-field"])
        XCTAssertFalse(app.switches["custom-action-fallback-toggle"].exists,
                       "with no slot there is no first argument to seed, so no fallback toggle")

        // Add a free-text slot → the toggle is offered.
        setText("https://example.com/?q={q}", in: app.textFields["custom-action-url-field"])
        XCTAssertTrue(app.switches["custom-action-fallback-toggle"].waitForExistence(timeout: 5),
                      "a free-text first argument enables the fallback toggle")
    }

    // MARK: - Editor: drag-to-reorder sets the fill order

    /// Dragging one argument row above another sets the fill order — the breadcrumb's
    /// asking order — leaving the URL untouched. Asserted by the two rows swapping
    /// vertical position after the drag (ADR 0021, issue #94).
    @MainActor
    func testDragReordersArgumentRows() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("things:///add?title={title}&notes={notes}", in: app.textFields["custom-action-url-field"])
        let titleRow = app.textFields["custom-action-arg.title"]
        let notesRow = app.textFields["custom-action-arg.notes"]
        XCTAssertTrue(titleRow.waitForExistence(timeout: 5))
        XCTAssertTrue(notesRow.waitForExistence(timeout: 5))

        // Default fill order is URL order: title sits above notes.
        XCTAssertLessThan(titleRow.frame.minY, notesRow.frame.minY, "title starts above notes")

        // Enter edit mode; the reorder grip sits at each row's trailing edge. Drag
        // from the notes grip up to the top of the title row — a coordinate drag is
        // the most reliable cross-version reorder gesture.
        app.buttons["custom-action-reorder"].tap()
        let grip = notesRow.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        let target = titleRow.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.0))
        grip.press(forDuration: 0.7, thenDragTo: target)

        // After the drag the rows have swapped: notes now sits above title.
        let reNotes = app.textFields["custom-action-arg.notes"]
        let reTitle = app.textFields["custom-action-arg.title"]
        XCTAssertTrue(reNotes.waitForExistence(timeout: 5))
        XCTAssertLessThan(reNotes.frame.minY, reTitle.frame.minY,
                          "dragging notes above title reordered the fill order")
    }

    // MARK: - End-to-end: a multi-argument Custom Action runs through the breadcrumb

    /// Authoring a multi-slot, fallback-flagged Custom Action through the new editor
    /// and running it: selecting it from the fallback region seeds-and-commits the
    /// typed query as the first slot and continues to the second, and committing the
    /// last slot completes the run — opening the fully-formed URL at the edge.
    @MainActor
    func testMultiArgumentCustomActionRunsEndToEnd() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("Add Todo", in: app.textFields["custom-action-name-field"])
        setText("things:///add?title={title}&notes={notes}", in: app.textFields["custom-action-url-field"])

        // Flag it as a fallback so the typed query seeds its first slot.
        let toggle = app.switches["custom-action-fallback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        flip(toggle, to: true)

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled, "the authored multi-slot fallback validates for Save")
        save.tap()

        // The new row is listed on the page (the editor wrote to storage), then pop
        // back to the launcher.
        XCTAssertTrue(app.staticTexts["Add Todo"].waitForExistence(timeout: 10),
                      "the authored Custom Action is listed on the Management page")
        goBackHome(app)

        // Type a query and pick the fallback row.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the launcher input is back after popping the page")
        input.tap()
        input.typeText("buy milk")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Add Todo")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the authored Custom Action surfaces as a fallback row")
        row.tap()

        // Seed-and-commit sealed the first slot ("buy milk" → title) and the
        // breadcrumb continues at the second slot — a multi-slot fallback does not
        // finish in one tap.
        XCTAssertTrue(app.buttons["pill-0"].waitForExistence(timeout: 5),
                      "the typed query seeded the first slot as a sealed pill")
        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(captureField.waitForExistence(timeout: 5),
                      "a multi-slot fallback continues collecting the next slot")

        // Fill the second slot and commit it (the final step): the run completes and
        // opens the fully-formed URL, dismissing the breadcrumb.
        captureField.tap()
        captureField.typeText("and eggs\n")
        XCTAssertTrue(
            captureField.waitForNonExistence(timeout: 5),
            "committing the last slot completes the run rather than trapping the user mid-slot"
        )
    }

    /// Flips a SwiftUI Toggle: tapping the row-spanning switch's center misses the
    /// control, so tap the nested switch when the OS exposes one, else a trailing-edge
    /// coordinate tap — the same approach as ProviderDisableUITests.
    @MainActor
    private func flip(_ toggle: XCUIElement, to on: Bool) {
        let landed = NSPredicate(format: "value == %@", on ? "1" : "0")
        if (toggle.value as? String) == (on ? "1" : "0") { return }
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap() } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3) != .completed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3)
        }
    }
}
