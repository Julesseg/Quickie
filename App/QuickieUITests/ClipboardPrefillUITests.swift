import XCTest
import UIKit

/// The clipboard-prefill acceptance criteria that can only be observed by
/// driving the real app: the paste chip appears on Home exactly when the
/// clipboard holds text, and stays absent when it doesn't (issue #10; ADR 0002).
/// The *decision* logic is covered deterministically by QuickieCore's
/// `ClipboardPrefillTests`; these verify the iOS wiring around it — the silent
/// `hasStrings` gate and the system paste control's presence.
///
/// We seed the simulator's shared pasteboard from the test process. Only the
/// banner-free `hasStrings` metadata drives the chip's visibility, so these
/// assertions never trip the system paste alert (which fires on content reads
/// the app makes only behind a user tap).
final class ClipboardPrefillUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with a clean signals slate (mirrors the other UI suites): the
    /// no-chip test asserts on the pre-anything `home-placeholder`, which only
    /// shows with no Favorites and no Recents — an earlier suite's row taps
    /// persist frecency across launches and would otherwise swap Home to the
    /// Recent list, making this suite pass or fail by alphabetical run order.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-signals"]
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    @MainActor
    func testPasteChipAppearsWhenClipboardHasText() throws {
        UIPasteboard.general.string = "https://example.com"

        let app = launchApp()

        XCTAssertTrue(
            app.buttons["clipboard-paste-chip"].waitForExistence(timeout: 10),
            "with text on the clipboard, Home should offer the paste chip"
        )
    }

    @MainActor
    func testNoPasteChipWhenClipboardHasNoText() throws {
        UIPasteboard.general.items = []

        let app = launchApp()

        // Wait for Home to be up before asserting the chip's absence, so we're
        // not racing a not-yet-rendered screen.
        XCTAssertTrue(
            app.staticTexts["home-placeholder"].waitForExistence(timeout: 10),
            "Home should be showing for the empty launch query"
        )
        XCTAssertFalse(
            app.buttons["clipboard-paste-chip"].exists,
            "with an empty clipboard, no paste chip should be offered"
        )
    }
}
