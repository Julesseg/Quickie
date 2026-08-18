import XCTest

/// The **Shelf** as a launcher surface (CONTEXT.md → Shelf; ADR 0037; issue #242): the
/// row of circular, icon-only glass buttons above the input — when it shows, what a tap
/// does, and what a long press opens.
///
/// Its two pure rules (the visibility/seed rule, the peek sizing) are pinned
/// deterministically in QuickieCore's `FallbackShelfTests`; these prove the wiring the
/// simulator alone can show. `FallbackShelfUITests` covers the other half of the tier —
/// the Fallbacks page's Shelf section and the promotion ladder.
///
/// A UI-test launch starts with an **empty Shelf** (`FallbacksStore.launch`), so every
/// test here shelves the member it cares about first rather than leaning on the
/// first-run seed. Shelf buttons carry their action's id **prefixed** with `shelf.`,
/// which is what keeps a Shelf button from answering an assertion about the bottom
/// fallback region the shelved action has just vacated.
final class ShelfRowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // A clean fallback slate (the reset clears both tier lists) and instant motion —
        // animated transitions at automation speed churn SwiftUI's DisplayList cache
        // into an internal assertion (issue #79).
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    /// Promotes the fallback titled `title` onto the Shelf through the real page — the
    /// only way a member gets there — and returns to the launcher. Works from either
    /// rung: Active rows and pool rows both carry the shelf button.
    @MainActor
    private func shelve(_ app: XCUIApplication, title: String) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'fallbacks' surfaces its command row")
        command.tap()

        // On a short screen (CI runs on iPhone SE) the row can land outside the fold,
        // and the page is three sections tall, so walk it into the render tree — both
        // directions, the newer idiom `FallbackShelfUITests` settled on: rewind to the
        // top first, then walk down, so a row above the current viewport is found too.
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        for _ in 0..<4 where !row.exists { app.swipeDown() }
        for _ in 0..<5 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(title) is listed on the Fallbacks page")
        let shelfButton = row.buttons["Move to the shelf"]
        XCTAssertTrue(shelfButton.waitForExistence(timeout: 5), "the row carries the shelf button")
        shelfButton.tap()

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the launcher input is back after popping the page")
    }

    /// The Shelf means "ways to use *this* query", so it is hidden on an empty one and
    /// appears the moment there is something to seed — and goes again when the query is
    /// deleted.
    @MainActor
    func testTheShelfShowsOnlyWhileTheQueryIsNonEmpty() throws {
        let app = launchApp()
        shelve(app, title: "Save for later")

        let shelfButton = app.buttons["shelf.builtin.save-for-later"]
        XCTAssertFalse(shelfButton.waitForExistence(timeout: 3),
                       "an empty query hides the Shelf entirely — a capture is started from Home instead")

        let input = app.textFields["search-input"]
        input.tap()
        input.typeText("dentist")
        XCTAssertTrue(shelfButton.waitForExistence(timeout: 5),
                      "a typed query brings the shelved fallback up as a button above the input")

        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "dentist".count))
        XCTAssertTrue(shelfButton.waitForNonExistence(timeout: 5),
                      "deleting the query hides the Shelf again")
    }

    /// Tapping a Shelf button **seeds-and-commits** the typed query as the action's
    /// first Argument, exactly like tapping a fallback-region row: a multi-argument
    /// member seals its first step and continues at step 2 rather than opening empty.
    @MainActor
    func testTappingAShelfButtonSeedsAndCommitsTheTypedQuery() throws {
        // New Reminder ships eligible but pooled, and its title → due date → list
        // breadcrumb is the clearest witness that the seed landed. The EventKit edge is
        // stubbed because XCUITest cannot pre-grant the Reminders permission dialog.
        let app = launchApp(["-uitest-stub-reminders"])
        shelve(app, title: "New Reminder")

        let input = app.textFields["search-input"]
        input.tap()
        input.typeText("call the dentist")

        let shelfButton = app.buttons["shelf.builtin.new-reminder"]
        XCTAssertTrue(shelfButton.waitForExistence(timeout: 5), "the shelved capture is offered for the query")
        shelfButton.tap()

        // The title step is already sealed — the tap committed the query into it — so
        // the breadcrumb is standing on the *due date* step, not asking for a title.
        XCTAssertTrue(app.buttons["capture-set-date"].waitForExistence(timeout: 10),
                      "seed-and-commit sealed the title and continued at step 2")
        let titlePill = app.buttons["pill-0"]
        XCTAssertTrue(titlePill.waitForExistence(timeout: 5), "the seeded title is a sealed pill")
        XCTAssertTrue(titlePill.label.localizedCaseInsensitiveContains("call the dentist"),
                      "the sealed pill holds the typed query verbatim")
    }

    /// The buttons are icon-only, so a long press has to say what one *is* — and it
    /// says it in the same menu every other Action surface shows (CONTEXT.md → Shelf;
    /// Secondary action): the action's title as the menu's non-action first row, above
    /// the verbs and the Pin item. Crucially the hold *only* opens the menu: lifting
    /// the finger must not also run the action, or reading the title could never save
    /// you from the wrong one.
    ///
    /// Menu items are asserted to exist rather than fired: XCUITest can surface a
    /// SwiftUI context-menu item but cannot run its action (the menu is a separate
    /// remote view) — the same limit `SecondaryActionUITests` documents.
    @MainActor
    func testLongPressingAShelfButtonOpensTheActionsMenuWithoutRunningIt() throws {
        let app = launchApp(["-uitest-stub-reminders"])
        shelve(app, title: "New Reminder")

        let input = app.textFields["search-input"]
        input.tap()
        input.typeText("dentist")

        let shelfButton = app.buttons["shelf.builtin.new-reminder"]
        XCTAssertTrue(shelfButton.waitForExistence(timeout: 5), "the shelved capture is offered for the query")
        shelfButton.press(forDuration: 1.0)

        // Scoped to the menu's own cells: the pressed Shelf button carries the same
        // title as its accessibility label, so an app-wide lookup would be answered by
        // the button itself and pass whether or not the menu ever opened.
        let titleRow = app.cells.buttons["New Reminder"].firstMatch
        XCTAssertTrue(titleRow.waitForExistence(timeout: 5),
                      "the long-press menu names the icon-only button it was opened from")
        XCTAssertFalse(titleRow.isEnabled,
                       "…as a non-action row — a label, not a verb that does nothing")
        XCTAssertTrue(app.buttons["Copy action deeplink"].exists,
                      "…and it is the shared Action menu, carrying the row's own verbs")
        XCTAssertTrue(app.buttons["Pin as Favorite"].exists,
                      "…and its Pin item, exactly as the same action's result row would")
        XCTAssertFalse(app.buttons["capture-set-date"].exists,
                       "opening the menu does not also run the action")
    }
}
