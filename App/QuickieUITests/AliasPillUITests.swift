import XCTest

/// The UI-only acceptance for the **Alias pill** (CONTEXT.md → Alias pill; issue
/// #196): a Custom Action with a user-authored alias wears that alias as a dim
/// capsule after its title on the shared result row, so the user re-learns the
/// aliases they defined. The per-Action carve-outs (built-in commands and Pile
/// entries never pill) and the single-source bolding are covered deterministically
/// by QuickieCore's AliasPillTests; this proves the pill actually renders on the
/// real result row, driven through the default-seeded GitHub link.
///
/// GitHub is the clean probe: its title "GitHub" carries no "gh" substring, so an
/// accessibility label containing "gh" can only be the pill — isolating the pill
/// from the title text without depending on bold rendering (which XCUITest can't
/// read anyway).
final class AliasPillUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// Typing a query that name-matches the default-seeded **GitHub** static Custom
    /// Action surfaces its row wearing its "gh" alias pill. The row is a ranked name
    /// match (a static link is not fallback-eligible), rendered by the shared
    /// `ActionRow`, so the pill it shows here is the same one the Home Recent list
    /// renders.
    @MainActor
    func testCustomActionRowWearsAliasPill() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("github")

        let row = app.buttons["seed.link.github"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "typing 'github' surfaces the seeded GitHub row")

        // The pill renders one of two ways depending on how SwiftUI resolves the
        // labelled Button's accessibility tree: either the "gh" folds into the row's
        // aggregated label, or the pill stays its own identified static text. Accept
        // both — the title "GitHub" carries no lowercase "gh", so either signal can
        // only be the alias pill.
        let labelCarriesPill = row.label.range(of: "gh") != nil
        let pillElement = app.staticTexts["alias-pill.seed.link.github"]
        let pillIsElement = pillElement.exists || pillElement.waitForExistence(timeout: 2)
        XCTAssertTrue(labelCarriesPill || pillIsElement,
                      "the GitHub row wears its 'gh' alias pill (label: \(row.label))")
    }
}
