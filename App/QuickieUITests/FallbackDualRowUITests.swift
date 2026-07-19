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
}
