import XCTest

/// The UI-drivable acceptance for the Favorites widget's **frecency outbox** (ADR
/// 0025; issue #126): a widget-run selection appends `(actionId, timestamp)` to the
/// App Group outbox, and the app drains it into `SignalsStore` on foreground — so
/// the run surfaces in Home's Frecency "Recent" list without the user ever having
/// tapped a row in-app. The outbox codec/merge and the button classification are
/// Core-covered (`WidgetRunOutboxTests`, `FavoritesWidgetSnapshotTests`); this
/// proves the app-side drain wiring end to end: outbox key → drain →
/// `SignalsStore.record` → Recent row.
///
/// XCUITest cannot tap a Home-Screen widget (it lives outside the app under
/// SpringBoard), so the outbox is seeded through the `-uitest-seed-widget-run`
/// launch argument — a *real* `FavoritesWidgetStore.recordRun` write performed in
/// `QuickieApp.init`, before `RootView`'s launch drain runs — the same
/// "drive the real path" seam as `-uitest-seed-frecent` and the entry trigger.
final class FavoritesWidgetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A drained widget run surfaces in Frecency: seed one pending outbox event for
    /// the Settings command, launch on a clean slate, and — with no typing and no
    /// taps — Home's Recent list shows the Settings row. Before the drain existed
    /// this state was unreachable: a fresh launch with untouched signals always
    /// rendered the empty-Home placeholder.
    @MainActor
    func testSeededWidgetRunSurfacesInRecents() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-seed-widget-run", "builtin.settings",
            "-uitest-instant-motion",
        ]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")

        // The drained run is credited into Frecency, so Home renders the Settings
        // command as a Recent row — without a single in-app selection having
        // happened this launch.
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "the seeded widget-run outbox event should drain into Frecency and surface Settings in Home's Recent list"
        )
        XCTAssertFalse(
            app.staticTexts["home-placeholder"].exists,
            "Home is no longer empty once the widget run is credited"
        )
    }
}
