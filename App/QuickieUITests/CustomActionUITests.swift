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

    /// The fallback toggle, scrolled into view first. Each argument row now carries a
    /// type picker, so a multi-slot form's taller rows can push the toggle below the
    /// fold — and SwiftUI's `Form` drops off-screen rows from the accessibility tree,
    /// so it must be scrolled back into existence before it can be found (issue #96).
    @MainActor
    private func revealFallbackToggle(_ app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["custom-action-fallback-toggle"]
        for _ in 0..<4 {
            if toggle.waitForExistence(timeout: 2) { return toggle }
            app.swipeUp()
        }
        return toggle
    }

    // MARK: - Editor: live slot detection + rename rewrites the token

    /// Typing the URL grows an argument row per `{name}` slot, deleting a token drops
    /// its row immediately (hard mirror), and renaming a row rewrites the URL token
    /// **live, per keystroke** — the whole point of the live-mirroring editor (ADR
    /// 0021). URL edits are driven by backspacing from the end (the cursor sits there
    /// after typing) and over-deleting to clear, so the field content is deterministic
    /// without reading it back — a full-field re-type is unreliable when the URL shrinks.
    @MainActor
    func testEditorLiveMirrorsSlotsAndRenameRewritesToken() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        let urlField = app.textFields["custom-action-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()

        // Two slots typed → two argument rows appear, mirroring the template.
        urlField.typeText("things:///add?title={title}&notes={notes}")
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5),
                      "the {title} slot mirrors an argument row")
        XCTAssertTrue(app.textFields["custom-action-arg.notes"].waitForExistence(timeout: 5),
                      "the {notes} slot mirrors an argument row")

        // Backspace the "&notes={notes}" suffix from the end → the {notes} row drops
        // immediately (hard mirror), no stashing.
        let notesSuffix = "&notes={notes}"
        urlField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: notesSuffix.count))
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["custom-action-arg.notes"].exists,
                       "deleting the token drops its row — no stashing")

        // Clear the field (over-delete is safe) and type a numeric-slot URL: the row
        // auto-labels, and typing a name into it rewrites the URL token live.
        urlField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60))
        urlField.typeText("app://x?a={1}")
        let numericRow = app.textFields["custom-action-arg.1"]
        XCTAssertTrue(numericRow.waitForExistence(timeout: 5), "a numeric {1} slot appears as a row")
        numericRow.tap()
        numericRow.typeText("title")

        // The token in the URL is rewritten in place, and the row now keys off the
        // chosen name.
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5),
                      "renaming the row rewrites the URL token live")
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

    // Note on drag-to-reorder: the fill-order reorder *logic* — that a drag sets the
    // breadcrumb's asking order, decoupled from URL order, and persists across
    // template edits — is covered deterministically by QuickieCore's
    // CustomActionEditorTests (`reorderSetsAskingOrder`,
    // `reorderPersistsAcrossTemplateEdits`, `fillOrderDrivesAskingOrderNotURLOrder`).
    // The edit-mode reorder affordance (`custom-action-reorder`) is present in the
    // editor; a raw drag gesture on the reorder grip is too environment-sensitive to
    // assert reliably here, so it isn't driven as an XCUITest.

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
        let toggle = revealFallbackToggle(app)
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

    /// Sets an argument row's type via its menu type picker (issue #96): tap the menu,
    /// then the option. Element-type-agnostic on the picker, since a Form menu Picker
    /// surfaces as a button on most OS versions but not all.
    @MainActor
    private func setType(_ app: XCUIApplication, token: String, to label: String) {
        let picker = app.descendants(matching: .any)
            .matching(identifier: "custom-action-type.\(token)").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the \(token) row shows a type picker")
        picker.tap()
        // A menu Picker's options surface as buttons on most OS versions, menu items on
        // some — take whichever appears.
        let button = app.buttons[label]
        let menuItem = app.menuItems[label]
        if button.waitForExistence(timeout: 3) {
            button.tap()
        } else if menuItem.waitForExistence(timeout: 3) {
            menuItem.tap()
        } else {
            XCTFail("the \(label) type option did not appear in the menu")
        }
    }

    // MARK: - Editor: per-row type picker + choice/date config

    /// Setting an argument to **Choice** reveals the inline options editor, and Save
    /// stays gated until at least one non-blank option is entered (ADR 0021, issue
    /// #96) — a choice with no options presents an empty runtime list.
    @MainActor
    func testChoiceTypeRevealsOptionsAndGatesSave() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("Add Todo", in: app.textFields["custom-action-name-field"])
        setText("things:///add?list={list}", in: app.textFields["custom-action-url-field"])

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled, "a free-text slot validates before the type changes")

        // Switch the slot to Choice → an empty option field appears and Save is
        // regated on it (no options yet).
        setType(app, token: "list", to: "Choice")
        let option = app.textFields["custom-action-choice-option.list.0"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "choosing Choice reveals an inline option field")
        XCTAssertFalse(save.isEnabled, "a choice with no options can't be saved")

        // Enter an option → Save re-enables.
        setText("Today", in: option)
        XCTAssertTrue(save.isEnabled, "a choice with a non-empty option validates for Save")
    }

    /// Setting an argument to **Date** reveals its output-format override fields, and
    /// a date/number/choice *first-by-fill-order* argument disables the fallback flag
    /// — the gate that "now bites" once types land (ADR 0021, issue #96).
    @MainActor
    func testDateTypeRevealsFormatsAndDisablesFallback() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("When", in: app.textFields["custom-action-name-field"])
        setText("things:///add?when={when}", in: app.textFields["custom-action-url-field"])

        // A text first argument leaves the fallback toggle enabled.
        let toggle = revealFallbackToggle(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled, "a free-text first argument allows the fallback flag")

        // Switch the (only, first) slot to Date → format fields appear and the
        // fallback flag is disabled (a date-first action has nowhere to seed the query).
        setType(app, token: "when", to: "Date")
        XCTAssertTrue(app.textFields["custom-action-date-format.when"].waitForExistence(timeout: 5),
                      "a date slot reveals its single output-format field")
        XCTAssertFalse(toggle.isEnabled, "a date first argument disables the fallback flag")
    }

    // MARK: - End-to-end: typed arguments run through the breadcrumb

    /// A Custom Action mixing a text, a date, and a choice slot runs end to end: the
    /// breadcrumb morphs the control per type — keyboard (seed) → date picker →
    /// fuzzy option list — and committing the final slot opens the filled URL,
    /// dismissing the breadcrumb (issue #96, the flagship acceptance shape).
    @MainActor
    func testTypedArgumentsRunEndToEnd() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("Add Todo", in: app.textFields["custom-action-name-field"])
        // Fill order follows URL order: title (text) → when (date) → list (choice).
        setText("things:///add?title={title}&when={when}&list={list}",
                in: app.textFields["custom-action-url-field"])
        setType(app, token: "when", to: "Date")
        setType(app, token: "list", to: "Choice")
        setText("Today", in: app.textFields["custom-action-choice-option.list.0"])

        // Flag it as a fallback so the typed query seeds the first (text) slot.
        let toggle = revealFallbackToggle(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        flip(toggle, to: true)

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled, "the typed multi-slot fallback validates for Save")
        save.tap()

        XCTAssertTrue(app.staticTexts["Add Todo"].waitForExistence(timeout: 10),
                      "the authored Custom Action is listed on the Management page")
        goBackHome(app)

        // Type a query and pick the fallback row → seeds the title, advances to the
        // date step.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("buy milk")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add Todo")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the authored Custom Action surfaces as a fallback row")
        row.tap()

        XCTAssertTrue(app.buttons["pill-0"].waitForExistence(timeout: 5),
                      "the typed query seeded the first slot")

        // The date step shows its in-place picker + Set button; commit the default date.
        let setDate = app.buttons["capture-set-date"]
        XCTAssertTrue(setDate.waitForExistence(timeout: 5), "the date slot morphs to the date picker")
        setDate.tap()

        // The choice step shows the fuzzy option list; pick the option to complete.
        let choice = app.buttons["choice-Today"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the choice slot morphs to the fuzzy option list")
        choice.tap()

        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 5),
                      "committing the final slot completes the run and returns to the launcher")
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
