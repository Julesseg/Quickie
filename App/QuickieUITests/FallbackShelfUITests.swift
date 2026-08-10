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
    /// iPhone SE) a row can land outside the fold, and the page is a section taller now
    /// that the Shelf leads it, so nudge it into the render tree first.
    ///
    /// Searches **both** directions, unlike the older suites' scroll-down-only helper:
    /// a row promoted up the ladder moves *toward the top of the page* (pool → Active →
    /// Shelf), so after a tap the row this returns is often above the current viewport,
    /// not below it. Rewind to the top first, then walk down.
    @MainActor
    private func cell(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        for _ in 0..<4 where !cell.exists { app.swipeDown() }
        for _ in 0..<5 where !cell.exists { app.swipeUp() }
        return cell
    }

    /// Scrolls the page back to the top so two rows expected to be adjacent are in the
    /// same snapshot — frames from different scroll positions aren't comparable.
    @MainActor
    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown() }
    }

    /// Empties the launcher input. `openFallbacksPage` types a fresh query, so a test
    /// that has already typed something must clear it first — otherwise the two run
    /// together ("dentist" + "fallbacks") and no command row matches.
    @MainActor
    private func clearInput(_ app: XCUIApplication, count: Int) {
        let input = app.textFields["search-input"]
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
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

        clearInput(app, count: "dentist".count)
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

        // Save for later ships in Active, below the five search seeds — far enough down
        // that it and the first Active row are never in one snapshot, so the ordering
        // assertion below waits until the two are adjacent.
        let saveCell = cell(app, titled: "Save for later")
        XCTAssertTrue(saveCell.waitForExistence(timeout: 10), "Save for later is on the page")

        // Shelve it, then bring it back down.
        saveCell.buttons["Move to the shelf"].tap()
        let shelved = cell(app, titled: "Save for later")
        let unshelve = shelved.buttons["Remove from the shelf"]
        XCTAssertTrue(unshelve.waitForExistence(timeout: 5), "the shelved row offers its demote minus")
        unshelve.tap()

        // It comes back as an ordinary Active row…
        let restored = cell(app, titled: "Save for later")
        XCTAssertTrue(restored.buttons["Remove from active fallbacks"].waitForExistence(timeout: 5),
                      "a demoted Shelf member is an ordinary Active row again")

        // …at the *top* of Active rather than the bottom: it now sits directly above
        // the seeded web search that used to lead the section. Both are Active's first
        // two rows, so one rewind puts them in the same snapshot and their frames are
        // comparable (the exact placement rule is pinned in Core's FallbackTiersTests —
        // this is the wiring check).
        scrollToTop(app)
        let webSearch = cell(app, titled: "Search the web")
        XCTAssertTrue(webSearch.waitForExistence(timeout: 5), "the seeded web-search fallback is listed")
        XCTAssertLessThan(cell(app, titled: "Save for later").frame.minY, webSearch.frame.minY,
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
