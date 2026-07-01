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

    @MainActor
    func testPasteChipAppearsWhenClipboardHasText() throws {
        UIPasteboard.general.string = "https://example.com"

        let app = XCUIApplication()
        // Reset the persisted app-level toggles (issue #65): a prior test that
        // flipped Clipboard prefill off would otherwise suppress the chip here.
        app.launchArguments += ["-uitest-reset-signals"]
        app.launch()

        XCTAssertTrue(
            app.buttons["clipboard-paste-chip"].waitForExistence(timeout: 10),
            "with text on the clipboard, Home should offer the paste chip"
        )
    }

    @MainActor
    func testNoPasteChipWhenClipboardHasNoText() throws {
        UIPasteboard.general.items = []

        let app = XCUIApplication()
        // Same clean slate as above — and a cleared Frecency keeps Home on the
        // placeholder this test waits for.
        app.launchArguments += ["-uitest-reset-signals"]
        app.launch()

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
