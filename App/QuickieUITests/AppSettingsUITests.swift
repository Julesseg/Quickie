import XCTest
import UIKit

/// The app-level Settings toggles' acceptance criteria (issue #65) that can only
/// be observed by driving the real app: the Settings page shows the app-level
/// section (Appearance, Clipboard prefill, Show Recents), and flipping a toggle
/// actually changes the Home surface it gates. The *decision* logic — the chip's
/// offer and the Recent list's contents — is covered deterministically by
/// QuickieCore's `ClipboardPrefillTests` and `HomeTests`; these verify the wiring
/// from the persisted toggle to the rendered surface.
///
/// Every launch passes `-uitest-reset-signals`: the toggles persist in the App
/// Group defaults, so a test that flips one off must start (and leave every later
/// test starting) from the reset-to-on slate `QuickieApp` restores under the flag.
final class AppSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-signals"]
        app.launch()
        return app
    }

    /// Types "settings" into the auto-focused input and opens the always-present
    /// Settings command row (Quickie ships no default Quicklinks, so it is the
    /// reliable top match). Leaves the app on the pushed Settings page.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist")
        input.tap()
        input.typeText("settings")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "typing 'settings' surfaces the Settings command")
        row.tap()
    }

    /// Pops the pushed Settings page back to the launcher via the navigation
    /// bar's back button.
    @MainActor
    private func goBackHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed Settings page shows a back button")
        back.tap()
    }

    /// Flips a Form `Toggle` off and asserts it landed. Tapping the row-spanning
    /// switch element's center is a no-op (it misses the control), so tap the
    /// nested switch when the OS exposes one, and fall back to a trailing-edge
    /// coordinate tap — where the control actually sits — when it doesn't.
    @MainActor
    private func flipOff(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let isOff = NSPredicate(format: "value == '0'")
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isOff, object: toggle)], timeout: 3) != .completed {
            // The first mechanism didn't reach the control — try the other one.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isOff, object: toggle)], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, "0", "the tap flipped the toggle off")
    }

    /// Settings shows the app-level section: Appearance plus the two toggles,
    /// both defaulting to on (issue #65 AC #1, #4).
    @MainActor
    func testSettingsShowsAppLevelSectionWithTogglesOnByDefault() throws {
        let app = launchApp()
        openSettings(app)

        // Element-type-agnostic: a Form menu Picker surfaces differently across
        // OS versions (a button on most), so match the identifier on anything.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "appearance-picker")
                .firstMatch.waitForExistence(timeout: 10),
            "the app-level section holds the Appearance picker"
        )

        let clipboard = app.switches["settings-clipboard-prefill"]
        XCTAssertTrue(clipboard.waitForExistence(timeout: 10), "the Clipboard prefill toggle exists")
        XCTAssertEqual(clipboard.value as? String, "1", "Clipboard prefill defaults to on")

        let recents = app.switches["settings-show-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: 10), "the Show Recents toggle exists")
        XCTAssertEqual(recents.value as? String, "1", "Show Recents defaults to on")
    }

    /// Turning off Show Recents hides the Frecency "Recent" list on Home (issue
    /// #65 AC #3). Opening Settings records a frecency event for the Settings
    /// command, so with the toggle on (the control leg) that row is Home's Recent
    /// list; flipping the toggle off then returning must leave Home without it —
    /// back to the bare placeholder, since nothing is pinned.
    @MainActor
    func testShowRecentsOffHidesTheRecentListOnHome() throws {
        let app = launchApp()

        // Control leg: running the Settings command records frecency, so after
        // popping back, Home shows it in the Recent list.
        openSettings(app)
        goBackHome(app)
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "with Show Recents on, the just-used Settings command appears in Home's Recent list"
        )

        // Home's Recent list renders the row with the same id as a result row —
        // tapping it re-opens Settings, where we flip the toggle off.
        app.buttons["builtin.settings"].tap()
        let recents = app.switches["settings-show-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: 10), "the Show Recents toggle exists")
        flipOff(recents)

        goBackHome(app)

        // Nothing is pinned and the Recent list is now hidden, so Home falls back
        // to the bare placeholder — and the used command's row is gone.
        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "with Show Recents off and no Favorites, Home shows the placeholder"
        )
        XCTAssertFalse(
            app.buttons["builtin.settings"].exists,
            "with Show Recents off, the Recent list (and its rows) is hidden on Home"
        )
    }

    /// Turning off Clipboard prefill suppresses the paste chip on Home (issue #65
    /// AC #2): with text on the clipboard the chip is offered (the control leg),
    /// and after flipping the toggle off it stays gone even though the clipboard
    /// still holds text. Only the banner-free `hasStrings` metadata drives the
    /// chip, so neither leg trips the system paste alert.
    @MainActor
    func testClipboardPrefillOffSuppressesThePasteChip() throws {
        UIPasteboard.general.string = "https://example.com"

        let app = launchApp()

        // Control leg: with the toggle on (the reset default), the chip is offered.
        XCTAssertTrue(
            app.buttons["clipboard-paste-chip"].waitForExistence(timeout: 10),
            "with Clipboard prefill on and text on the clipboard, Home offers the paste chip"
        )

        openSettings(app)
        let toggle = app.switches["settings-clipboard-prefill"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the Clipboard prefill toggle exists")
        flipOff(toggle)

        goBackHome(app)

        // Back on Home: the input is back (the query was cleared by the push) but
        // the chip must not return, even though the clipboard still holds text.
        XCTAssertTrue(
            app.textFields["search-input"].waitForExistence(timeout: 10),
            "the launcher input returns after popping Settings"
        )
        XCTAssertFalse(
            app.buttons["clipboard-paste-chip"].exists,
            "with Clipboard prefill off, the paste chip stays gone despite clipboard text"
        )
    }
}
