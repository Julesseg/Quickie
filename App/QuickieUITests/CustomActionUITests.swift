import XCTest

/// The UI-only acceptance criteria for the Custom Actions authoring surface
/// (CONTEXT.md → Custom Action; ADR 0021, issue #94) that can only be verified by
/// driving the real app on a simulator: the **live-mirroring editor** (typing the
/// URL grows argument rows, renaming a row rewrites the URL token, drag sets the
/// fill order, the derived eligibility note reflects the first argument, and Save is
/// gated), and one **end-to-end** breadcrumb run of a multi-argument Custom Action
/// authored through the new Management page and activated on the Fallbacks page.
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

    /// Activates an authored Custom Action as a fallback the way a user now does —
    /// there is no editor toggle (issue #114): open the Fallbacks page and tap the
    /// green plus on the action's row in the **Available** pool, promoting it to the
    /// active section, then pop back to the launcher. Assumes the launcher is showing
    /// with an empty query (opening the page via its command row clears the query).
    @MainActor
    private func activateAsFallback(_ app: XCUIApplication, title: String) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'fallbacks' surfaces the command row")
        command.tap()

        // The freshly authored action waits in the Available pool (newly eligible
        // actions are not auto-enabled). The pool sits below the pre-enabled Active
        // section, so scroll it into view if a lazy List hasn't realized it, then find
        // its row by title and tap its promote plus.
        let poolCell = app.cells.containing(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        var scrolls = 0
        while !poolCell.exists && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(poolCell.waitForExistence(timeout: 10), "the authored action waits in the fallback pool")
        let promote = poolCell.buttons["Add to active fallbacks"]
        XCTAssertTrue(promote.waitForExistence(timeout: 5), "the pool row offers a promote button")
        promote.tap()

        goBackHome(app)
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

    // MARK: - Editor: Save gating + slot-less static link

    /// Save is gated on a valid definition. A slot-less schemed URL is a valid **static
    /// link** (ADR 0030 — the former Quicklink), so it saves and shows the static-link
    /// note rather than a redirect; adding a slot turns it into a breadcrumb action.
    @MainActor
    func testSaveIsGatedAndSlotlessURLIsAStaticLink() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save is disabled with an empty name and no URL")

        // A slot-less schemed URL: the static-link note shows, and Save enables.
        setText("Docs", in: app.textFields["custom-action-name-field"])
        setText("https://example.com", in: app.textFields["custom-action-url-field"])
        XCTAssertTrue(app.staticTexts["custom-action-static-link-note"].waitForExistence(timeout: 5),
                      "a slot-less URL is a valid static link")
        XCTAssertTrue(save.isEnabled, "a named, schemed slot-less URL saves as a static link")

        // Add a slot → the argument row appears and Save stays enabled.
        setText("https://example.com/search?q={q}", in: app.textFields["custom-action-url-field"])
        XCTAssertTrue(app.textFields["custom-action-arg.q"].waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "a named, slotted, schemed URL validates for Save")
    }

    // MARK: - Editor: derived fallback eligibility note (no toggle)

    /// There is no fallback toggle anymore (issue #114) — eligibility is derived from
    /// shape. The editor shows only an informational note, which appears once the URL
    /// carries a slot and reads "can be a fallback" while the first argument is free
    /// text. The slot-less case shows the static-link note instead of the eligibility note.
    @MainActor
    func testEligibilityNoteReflectsFreeTextFirstArgument() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        // The retired toggle must be gone entirely.
        XCTAssertFalse(app.switches["custom-action-fallback-toggle"].exists,
                       "the fallback toggle is retired — eligibility is derived, not declared")

        // No slot yet → no eligibility note (the static-link note shows instead).
        setText("https://example.com", in: app.textFields["custom-action-url-field"])
        XCTAssertFalse(app.staticTexts["custom-action-eligibility-note"].exists,
                       "with no slot there is no argument, so no eligibility note")

        // Add a free-text slot → the note appears and reads that it can be a fallback.
        setText("https://example.com/?q={q}", in: app.textFields["custom-action-url-field"])
        let note = app.staticTexts["custom-action-eligibility-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5),
                      "a slotted URL shows the eligibility note")
        XCTAssertTrue((note.label).localizedCaseInsensitiveContains("can be a fallback"),
                      "a free-text first argument reads as fallback-eligible (was: \(note.label))")
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

    /// Authoring a multi-slot Custom Action, activating it on the Fallbacks page, and
    /// running it: selecting it from the fallback region seeds-and-commits the typed
    /// query as the first slot and continues to the second, and committing the last
    /// slot completes the run — opening the fully-formed URL at the edge.
    @MainActor
    func testMultiArgumentCustomActionRunsEndToEnd() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("Add Todo", in: app.textFields["custom-action-name-field"])
        setText("things:///add?title={title}&notes={notes}", in: app.textFields["custom-action-url-field"])

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled, "the authored multi-slot Custom Action validates for Save")
        save.tap()

        // The new row is listed on the page (the editor wrote to storage), then pop
        // back to the launcher.
        // The authored row sorts last (newest), below the default seed rows, so scroll
        // it into view before asserting rather than assuming it's on-screen.
        let authored = app.staticTexts["Add Todo"]
        var authoredScrolls = 0
        while !authored.exists && authoredScrolls < 6 {
            app.swipeUp()
            authoredScrolls += 1
        }
        XCTAssertTrue(authored.waitForExistence(timeout: 10),
                      "the authored Custom Action is listed on the Management page")
        goBackHome(app)

        // Activate it as a fallback on the Fallbacks page (its free-text first slot
        // makes it eligible; newly eligible actions wait in the pool until promoted).
        activateAsFallback(app, title: "Add Todo")

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

    // MARK: - Running a one-tap fallback resolves the query

    /// Running a **single-slot** fallback Custom Action completes in one tap — the
    /// seed-and-commit finishes inside the capture's `beginSession` without the
    /// breadcrumb ever taking over — and that run must **resolve the query** like any
    /// main action (CONTEXT.md → Main action): the input clears back to a clean Home.
    /// This is the case the `isActive` clear misses (the capture flips active
    /// true→false in one tick, netting no observable change), so it exercises the
    /// completion-driven clear directly. Uses a `things:///` scheme so the edge open is
    /// a no-op in a simulator without the app installed and the launcher stays put.
    @MainActor
    func testSingleSlotFallbackRunClearsInput() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("Quick Search", in: app.textFields["custom-action-name-field"])
        setText("things:///search?q={q}", in: app.textFields["custom-action-url-field"])

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled, "the single-slot Custom Action validates for Save")
        save.tap()

        // The authored row sorts last (newest); scroll it into view, then pop back.
        let authored = app.staticTexts["Quick Search"]
        var scrolls = 0
        while !authored.exists && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(authored.waitForExistence(timeout: 10),
                      "the authored Custom Action is listed on the Management page")
        goBackHome(app)

        // Activate it as a fallback (its free-text single slot makes it eligible) so a
        // typed query seeds-and-commits it in one tap.
        activateAsFallback(app, title: "Quick Search")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("hello world")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Quick Search")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the authored Custom Action surfaces as a fallback row")
        row.tap()

        // The one-tap run resolves the query: the launcher input clears back to a clean
        // Home (and with it, the Pending query Live Activity ends). We assert the field's
        // own value rather than Home's placeholder — by now Frecency has recorded
        // selections, so Home shows the Recent list, not the empty placeholder. Requiring
        // `exists` too keeps a stray breadcrumb from passing on a missing field. Before
        // the completion-driven clear the typed text lingered in the input, because the
        // immediate completion netted no observable `isActive` change.
        let cleared = expectation(
            for: NSPredicate(format: "exists == true AND NOT (value CONTAINS[c] %@)", "hello"),
            evaluatedWith: input
        )
        wait(for: [cleared], timeout: 5)
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

    /// Setting an argument to **Date** reveals its output-format override fields, and a
    /// date-first-by-fill-order argument flips the eligibility note to ineligible — the
    /// derived gate that "now bites" once types land (issue #96, #114).
    @MainActor
    func testDateTypeRevealsFormatsAndFlipsEligibilityNote() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("When", in: app.textFields["custom-action-name-field"])
        setText("things:///add?when={when}", in: app.textFields["custom-action-url-field"])

        // A text first argument reads as fallback-eligible.
        let note = app.staticTexts["custom-action-eligibility-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.localizedCaseInsensitiveContains("can be a fallback"),
                      "a free-text first argument reads as eligible (was: \(note.label))")

        // Switch the (only, first) slot to Date → format fields appear and the note
        // flips to ineligible (a date-first action has nowhere to seed the query).
        setType(app, token: "when", to: "Date")
        XCTAssertTrue(app.textFields["custom-action-date-format.when"].waitForExistence(timeout: 5),
                      "a date slot reveals its single output-format field")
        let ineligible = app.staticTexts["custom-action-eligibility-note"]
        XCTAssertTrue(ineligible.waitForExistence(timeout: 5))
        XCTAssertTrue(ineligible.label.localizedCaseInsensitiveContains("make its first argument free text"),
                      "a date first argument reads as ineligible (was: \(ineligible.label))")
    }

    // MARK: - Duplicate swipe action

    /// Swiping a Custom Action row offers a **Duplicate** action that forks a ` copy`
    /// alongside the original — a fast way to author a near-identical variant.
    @MainActor
    func testDuplicateSwipeActionForksTheRow() throws {
        let app = launchApp()
        openCustomActionsPage(app)
        openNewEditor(app)

        setText("Dupe Me", in: app.textFields["custom-action-name-field"])
        setText("https://example.com/?q={q}", in: app.textFields["custom-action-url-field"])
        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // The authored action sorts last (newest), below the default seed rows, so
        // scroll it into view before asserting rather than assuming it's on-screen.
        let original = app.staticTexts["Dupe Me"]
        var scrolls = 0
        while !original.exists && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(original.waitForExistence(timeout: 10), "the authored action is listed")

        // Reveal the row's swipe actions and tap Duplicate.
        original.swipeLeft()
        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5), "the row offers a Duplicate swipe action")
        duplicate.tap()

        // A ` copy` forks alongside the original, which remains.
        XCTAssertTrue(app.staticTexts["Dupe Me copy"].waitForExistence(timeout: 5),
                      "duplicating forks a ' copy' row")
        XCTAssertTrue(app.staticTexts["Dupe Me"].exists, "the original remains")
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

        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.isEnabled, "the typed multi-slot Custom Action validates for Save")
        save.tap()

        // The authored row sorts last (newest), below the default seed rows, so scroll
        // it into view before asserting rather than assuming it's on-screen.
        let authored = app.staticTexts["Add Todo"]
        var authoredScrolls = 0
        while !authored.exists && authoredScrolls < 6 {
            app.swipeUp()
            authoredScrolls += 1
        }
        XCTAssertTrue(authored.waitForExistence(timeout: 10),
                      "the authored Custom Action is listed on the Management page")
        goBackHome(app)

        // Activate it as a fallback (its free-text first slot makes it eligible) so the
        // typed query seeds the first (text) slot.
        activateAsFallback(app, title: "Add Todo")

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
}
