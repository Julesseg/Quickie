import XCTest

/// The UI-only acceptance criteria for the Custom Action unification slice
/// (CONTEXT.md → Custom Action; ADR 0021) that can only be verified by driving the
/// real app on a simulator: the interim Fallbacks add/edit sheet **reads and writes
/// the new Custom Action storage**, and a **multi-slot** text template authored
/// there runs through the breadcrumb — seed-and-commit sealing the first slot, the
/// remaining slot collected, and the final commit opening the fully-formed URL.
///
/// The token detection, percent-encoding fill, duplicate fan-out, and seed-and-commit
/// *logic* are covered deterministically by QuickieCore's CustomActionTests; these
/// prove the store + sheet + engine + capture wiring around them. Like the Shortcut
/// tests, the actual URL open leaves the app (or no-ops in a simulator without the
/// target app), so the reliable end-of-run signal is the breadcrumb dismissing —
/// the capture completed rather than trapping the user mid-slot.
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

    /// Opens the Fallbacks page and authors a Custom Action through the interim
    /// add sheet (name + URL template). The whole point of this slice's interim
    /// authoring: the sheet writes to the new `StoredCustomAction` storage.
    @MainActor
    private func authorCustomAction(_ app: XCUIApplication, title: String, template: String) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")

        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'fallbacks' surfaces the Fallbacks command")
        command.tap()

        let add = app.buttons["add-fallback-query"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the Fallbacks page offers an add button")
        add.tap()

        let titleField = app.textFields["fallback-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "the interim editor sheet has a name field")
        titleField.tap()
        titleField.typeText(title)

        let urlField = app.textFields["fallback-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText(template)

        let save = app.buttons["save-fallback-query"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    /// Pops the pushed Fallbacks page back to the launcher.
    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    /// The interim add/edit sheet reads and writes the new Custom Action storage
    /// (ADR 0021): a multi-slot template authored through it persists and appears as
    /// a deletable row on the Fallbacks page alongside the seeded web search.
    @MainActor
    func testInterimSheetWritesMultiSlotCustomActionToStorage() throws {
        let app = launchApp()
        authorCustomAction(app, title: "Add Todo", template: "things:///add?title={title}&notes={notes}")

        // Back on the Fallbacks page after the sheet dismissed: the new row is listed
        // (the sheet wrote to the new storage), next to the default web search.
        let row = app.staticTexts["Add Todo"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the authored Custom Action is listed on the Fallbacks page")
        XCTAssertTrue(app.staticTexts["Search the web"].exists, "the default web-search Custom Action is still seeded")
    }

    /// A multi-slot text template authored via the interim sheet runs through the
    /// breadcrumb (ADR 0021): selecting it from the fallback region seeds-and-commits
    /// the typed query as the first slot and continues to the second, and committing
    /// the last slot completes the run (opening the fully-formed URL at the edge).
    @MainActor
    func testMultiSlotCustomActionRunsThroughBreadcrumb() throws {
        let app = launchApp()
        authorCustomAction(app, title: "Add Todo", template: "things:///add?title={title}&notes={notes}")
        goBackHome(app)

        // Type a query and pick the fallback: a non-matching query surfaces the
        // fallback region, where the authored Custom Action rides.
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
        // breadcrumb continues at the second slot — a multi-slot fallback does *not*
        // finish in one tap. The sealed first pill and the still-present capture
        // field together prove it continued rather than completing or trapping.
        let firstPill = app.buttons["pill-0"]
        XCTAssertTrue(firstPill.waitForExistence(timeout: 5), "the typed query seeded the first slot as a sealed pill")
        let captureField = app.textFields["capture-input"]
        XCTAssertTrue(captureField.waitForExistence(timeout: 5), "a multi-slot fallback continues collecting the next slot")

        // Fill the second slot and commit it (the final step): the run completes and
        // opens the fully-formed URL at the platform edge, dismissing the breadcrumb.
        captureField.tap()
        captureField.typeText("and eggs\n")

        XCTAssertTrue(
            captureField.waitForNonExistence(timeout: 5),
            "committing the last slot completes the Custom Action run rather than trapping the user mid-slot"
        )
    }
}
