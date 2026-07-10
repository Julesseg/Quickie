import XCTest

/// UI-drivable acceptance for the **Actions widget** and **Action control** (ADR
/// 0027; issue #140) out-of-app run crediting. Both surfaces run a chosen Action
/// through the *same* button intents and the *same* Frecency outbox as the Favorites
/// widget (`FavoritesWidgetStore`): a copy / hand-off run completes without the app,
/// so it appends `(actionId, timestamp)` to the App Group outbox, and the app drains
/// it into `SignalsStore` on foreground (ADR 0025). The catalog eligibility rule, the
/// codec, and the id-join are Core-covered (`EligibleActionCatalogTests`); this proves
/// the drain surfaces a **catalog action** end to end.
///
/// Unlike `FavoritesWidgetUITests` (which seeds a built-in command), this seeds a run
/// of a *user-content* catalog action — an imported Shortcut, the shape a user would
/// actually bind to an Actions-widget cell or the Action control — and asserts it
/// lands in Home's Recent list. It exercises the join's premise from the app side:
/// the credited id resolves against the live catalog, so the run surfaces rather than
/// dangling.
///
/// XCUITest can tap neither a Home-Screen widget nor a Control Center control (both
/// live outside the app), so the run is seeded through the real
/// `FavoritesWidgetStore.recordRun` write via `-uitest-seed-widget-run`, and the
/// catalog action is made resolvable through the real import path via
/// `-uitest-seed-input-shortcuts` — the same "drive the real path" seams the Favorites
/// and Shortcut suites use.
final class ActionsWidgetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A widget/control run of an eligible catalog action surfaces in Frecency: import
    /// a Shortcut named "Timer" (a catalog member, `shortcut.timer`), seed one pending
    /// outbox event for it, launch on a clean slate, and — with no typing and no taps —
    /// Home's Recent list shows the Timer row. The seed lands after the launch reset, so
    /// the drain credits it onto a clean signals store.
    @MainActor
    func testWidgetRunOfCatalogActionSurfacesInRecents() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-seed-input-shortcuts", "Timer",
            "-uitest-seed-widget-run", "shortcut.timer",
            "-uitest-instant-motion",
        ]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")

        // The drained run is credited into Frecency, and the imported Shortcut resolves
        // in the catalog, so Home renders it as a Recent row — without a single in-app
        // selection this launch. Matched by label (like the Shortcut suite) so the row's
        // exact accessibility identity isn't assumed.
        let recentRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Timer")
        ).firstMatch
        XCTAssertTrue(
            recentRow.waitForExistence(timeout: 10),
            "an out-of-app widget/control run of a catalog action should drain into Frecency and surface it in Home's Recent list"
        )
        XCTAssertFalse(
            app.staticTexts["home-placeholder"].exists,
            "Home is no longer empty once the catalog-action run is credited"
        )
    }
}
