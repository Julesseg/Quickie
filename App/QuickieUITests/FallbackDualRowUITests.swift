import XCTest

/// The dual-row behaviour of an enabled Fallback (CONTEXT.md → Fallback Action;
/// issue #197): an enabled fallback whose name/alias matches the query surfaces
/// **twice** — a ranked name-match row (startable verb-first, breadcrumb empty) and
/// the bottom fallback-region row (seeds-and-commits the typed query). The seeded
/// web-search Fallback ("Search the web", pre-enabled on a fresh install) is the
/// fixture: typing "web" name-matches its title.
///
/// The finer ranking/region rules are pinned deterministically by QuickieCore's
/// `FallbackTests`/`RankingTests`; these acceptance tests confirm the behaviour on
/// the real app, where a single engine change flows through the region-carrying rows
/// and region-keyed run path from issue #195.
final class FallbackDualRowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // `--uitesting` re-seeds the default web-search Custom Action on every launch
        // (and pre-enables it as a fallback); `-uitest-reset-signals` keeps Home clean;
        // instant motion removes the row-insert spring from the timing.
        app.launchArguments += ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// Typing "web" surfaces the enabled web-search Fallback both as a ranked
    /// name-match and in the bottom fallback region — two rows with the same id
    /// (AC: "typing 'web' surfaces it both as a ranked match and in the bottom
    /// fallback region").
    @MainActor
    func testEnabledFallbackAppearsAsBothRankedMatchAndFallbackRow() throws {
        let app = launchApp()
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("web")

        let webRows = app.buttons.matching(identifier: "seed.web-search")
        // One appears first (the region row is always present); the dual row is the
        // ranked name-match arriving alongside it.
        let bothRows = expectation(
            for: NSPredicate(format: "count == 2"),
            evaluatedWith: webRows
        )
        wait(for: [bothRows], timeout: 5)
    }

    /// Pressing Return runs the Highlighted row — here the ranked name-match — which
    /// opens the breadcrumb **verb-first, empty at Argument 1**: the capture field
    /// appears with no seeded pill (AC: "selecting the ranked row opens the breadcrumb
    /// empty at Argument 1"; "Enter runs whichever row is the Highlighted result").
    @MainActor
    func testEnterOnRankedFallbackOpensBreadcrumbEmpty() throws {
        let app = launchApp()
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("web")

        // The ranked web-search is the only name-match for "web", so it is rank 0 —
        // the Highlighted row Enter runs.
        XCTAssertTrue(app.buttons.matching(identifier: "seed.web-search").firstMatch.waitForExistence(timeout: 5))

        // A lone trailing newline is the Return keypress on the vertical-axis field
        // (see InputBar): it fires the Highlighted result's Enter intent.
        input.typeText("\n")

        // Verb-first start: the single free-text Argument is prompted through the
        // breadcrumb, so the capture field appears and no pill was seeded.
        let capture = app.textFields["capture-input"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5),
                      "the ranked match starts verb-first, opening the breadcrumb at Argument 1")
        XCTAssertFalse(app.buttons["pill-0"].exists,
                       "a verb-first start seeds no pill — the breadcrumb begins empty")
    }

    /// The declared Fallbacks option is the narrow region gate: off removes the
    /// bottom fallback row without changing the action's name-match route.
    @MainActor
    func testFallbacksToggleHidesTheRegionButKeepsNameMatches() throws {
        let app = launchApp()
        openCustomActions(app)
        moveSaveForLaterToShelf(in: app)

        flip("setting-custom-actions.fallbacks", to: false, in: app)
        assertSaveForLaterRemainsShelved(in: app)

        goBackHome(app)
        let input = app.textFields["search-input"]
        input.tap()
        input.typeText("anything")
        XCTAssertFalse(app.buttons["shelf.builtin.save-for-later"].waitForExistence(timeout: 2),
                       "Fallbacks off hides the Shelf without changing its membership")
        XCTAssertFalse(app.buttons["seed.web-search"].waitForExistence(timeout: 2),
                       "Fallbacks off removes the bottom fallback row")

        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "anything".count))
        input.typeText("web")
        XCTAssertTrue(app.buttons["seed.web-search"].waitForExistence(timeout: 5),
                      "Fallbacks off leaves the action reachable by name")
    }

    /// The Custom Actions kind switch is the exceptional master over this page's
    /// fallback sections. Built-in captures remain ordinary name matches.
    @MainActor
    func testCustomActionsSwitchSilencesFallbacksButNotBuiltInNameMatches() throws {
        let app = launchApp()
        openCustomActions(app)
        moveSaveForLaterToShelf(in: app)

        flip("provider-enabled-custom-actions", to: false, in: app)

        // The disabled kind no longer resolves its page's cross-provider list. Turn it
        // back on while still on this page to prove the gate never rewrote the ladder,
        // then turn it off again for the launcher assertions below.
        flip("provider-enabled-custom-actions", to: true, in: app)
        assertSaveForLaterRemainsShelved(in: app)
        flip("provider-enabled-custom-actions", to: false, in: app)

        goBackHome(app)
        let input = app.textFields["search-input"]
        input.tap()
        input.typeText("anything")
        XCTAssertFalse(app.buttons["shelf.builtin.save-for-later"].waitForExistence(timeout: 2),
                       "Custom Actions off hides the Shelf without changing its membership")
        XCTAssertFalse(app.buttons["seed.web-search"].waitForExistence(timeout: 2),
                       "Custom Actions off removes its fallback region")

        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "anything".count))
        input.typeText("save")
        XCTAssertTrue(app.buttons["builtin.save-for-later"].waitForExistence(timeout: 5),
                      "a built-in capture remains reachable by name")
    }

    @MainActor
    private func openCustomActions(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("custom actions")
        let command = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()
    }

    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func moveSaveForLaterToShelf(in app: XCUIApplication) {
        let row = fallbackCell(app, titled: "Save for later")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Save for later is active by default")
        let shelve = row.buttons["Move to the shelf"]
        XCTAssertTrue(shelve.waitForExistence(timeout: 5), "an active fallback can move to the Shelf")
        shelve.tap()
        assertSaveForLaterRemainsShelved(in: app)
    }

    @MainActor
    private func assertSaveForLaterRemainsShelved(in app: XCUIApplication) {
        let row = fallbackCell(app, titled: "Save for later")
        XCTAssertTrue(row.buttons["Remove from the shelf"].waitForExistence(timeout: 5),
                      "the saved membership remains in the Custom Actions fallback list")
    }

    @MainActor
    private func fallbackCell(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        for _ in 0..<4 where !row.exists { app.swipeDown() }
        for _ in 0..<5 where !row.exists { app.swipeUp() }
        return row
    }

    /// SwiftUI exposes these Form toggles as a row-spanning element on some device
    /// families, so tap its nested switch when present and otherwise the trailing
    /// control coordinate. Assert the value so the acceptance test never mistakes a
    /// missed row tap for a loop regression.
    @MainActor
    private func flip(_ identifier: String, to on: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the \(identifier) toggle exists")
        let landed = NSPredicate(format: "value == %@", on ? "1" : "0")
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3) != .completed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landed, object: toggle)], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "the \(identifier) toggle reached its requested state")
    }
}
