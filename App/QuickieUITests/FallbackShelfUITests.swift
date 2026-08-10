import XCTest

/// The UI half of the Shelf tier (CONTEXT.md → Fallback list, Shelf; ADR 0037; issue
/// #241): the Fallbacks page's third section and the promotion ladder's placement
/// rules as the user experiences them — a shelf button on every Active and pool row,
/// a red minus on the Shelf that drops a member to the **top** of Active, and a
/// shelved action vacating the Result list's bottom fallback region.
///
/// The ladder's *rules* (disjointness, top-of-Active demotion, pruning, the seeded
/// defaults) are covered deterministically by QuickieCore's `FallbackTiersTests`;
/// these prove the page + store wiring around them. A UI-test launch starts with an
/// **empty Shelf** (`FallbacksStore.launch`), so each test promotes the members it
/// cares about rather than leaning on the first-run seed.
final class FallbackShelfUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A clean fallback slate (the reset also clears both tier lists) and instant
        // motion — animated row transitions at automation speed churn SwiftUI's
        // DisplayList cache into an internal assertion (issue #79).
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    @MainActor
    private func openFallbacksPage(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'fallbacks' surfaces its command row")
        command.tap()
    }

    /// The Fallbacks-page row (cell) whose title contains `title`, resolved by
    /// containment — the reliable way to reach a row's inline controls where a
    /// top-level id query over a lazy List row is flaky. On a short screen (CI runs on
    /// iPhone SE) a row can land below the fold, and the page is a section taller now
    /// that the Shelf leads it, so nudge it into the render tree first.
    @MainActor
    private func cell(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        var swipes = 0
        while !cell.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        return cell
    }

    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed page shows a back button")
        back.tap()
    }

    /// Promoting an Active fallback onto the Shelf takes it out of the Active section
    /// — and out of the Result list's bottom fallback region with it.
    @MainActor
    func testShelvingAnActiveFallbackRemovesItFromTheBottomRegion() throws {
        let app = launchApp()

        // Save for later is pre-enabled (Active), so it rides the bottom region for
        // any query before we touch anything.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("dentist")
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "an active capture is offered in the bottom fallback region")

        openFallbacksPage(app)
        let active = cell(app, titled: "Save for later")
        XCTAssertTrue(active.waitForExistence(timeout: 10), "Save for later is on the page")
        let shelve = active.buttons["Move to the shelf"]
        XCTAssertTrue(shelve.waitForExistence(timeout: 5), "an Active row carries the shelf button")
        shelve.tap()

        // It is now a Shelf member: its row's primary verb flipped to the Shelf's own
        // red minus, and it no longer offers to be shelved again.
        let shelved = cell(app, titled: "Save for later")
        XCTAssertTrue(shelved.buttons["Remove from the shelf"].waitForExistence(timeout: 5),
                      "a shelved fallback shows the Shelf section's demote minus")
        XCTAssertFalse(shelved.buttons["Move to the shelf"].exists,
                       "a Shelf row has no shelf button — it is already there")

        // …and it has vacated the bottom fallback region.
        goBackHome(app)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("dentist")
        XCTAssertFalse(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 3),
                       "a shelved fallback no longer rides the bottom region")
    }

    /// Demoting a Shelf member lands it at the **top** of Active — it was important
    /// enough to shelve, so it does not fall to the bottom like a pool promotion.
    @MainActor
    func testDemotingFromTheShelfLandsAtTheTopOfActive() throws {
        let app = launchApp()
        openFallbacksPage(app)

        // Save for later starts *below* the seeded web search in Active.
        let webSearch = cell(app, titled: "Search the web")
        XCTAssertTrue(webSearch.waitForExistence(timeout: 10), "the seeded web-search fallback is listed")
        let saveCell = cell(app, titled: "Save for later")
        XCTAssertTrue(saveCell.waitForExistence(timeout: 10), "Save for later is on the page")
        XCTAssertGreaterThan(saveCell.frame.minY, webSearch.frame.minY,
                             "the two captures ship below the search seeds in Active")

        // Shelve it, then bring it back down.
        saveCell.buttons["Move to the shelf"].tap()
        let shelved = cell(app, titled: "Save for later")
        let unshelve = shelved.buttons["Remove from the shelf"]
        XCTAssertTrue(unshelve.waitForExistence(timeout: 5), "the shelved row offers its demote minus")
        unshelve.tap()

        // It comes back at the top of Active — above the seeded web search it used to
        // sit under — and is demotable to the pool again like any Active row.
        let restored = cell(app, titled: "Save for later")
        XCTAssertTrue(restored.buttons["Remove from active fallbacks"].waitForExistence(timeout: 5),
                      "a demoted Shelf member is an ordinary Active row again")
        XCTAssertLessThan(restored.frame.minY, cell(app, titled: "Search the web").frame.minY,
                          "demoting from the Shelf inserts at the top of Active, not the bottom")
    }

    /// A pool row climbs straight onto the Shelf — no forced two-step climb through
    /// Active. New Reminder ships eligible but *not* pre-enabled, so it starts pooled.
    @MainActor
    func testAPoolRowCanBePromotedStraightToTheShelf() throws {
        let app = launchApp()
        openFallbacksPage(app)

        let pooled = cell(app, titled: "New Reminder")
        XCTAssertTrue(pooled.waitForExistence(timeout: 10), "New Reminder is fallback-eligible and pooled")
        XCTAssertTrue(pooled.buttons["Add to active fallbacks"].exists, "a pool row carries the promote plus")
        let shelve = pooled.buttons["Move to the shelf"]
        XCTAssertTrue(shelve.waitForExistence(timeout: 5), "a pool row carries the shelf button too")
        shelve.tap()

        let shelved = cell(app, titled: "New Reminder")
        XCTAssertTrue(shelved.buttons["Remove from the shelf"].waitForExistence(timeout: 5),
                      "the pool row landed on the Shelf in one step")
        XCTAssertFalse(shelved.buttons["Add to active fallbacks"].exists,
                       "it left the pool — it is a Shelf member now, not an available one")
    }
}
