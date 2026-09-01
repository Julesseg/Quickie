import XCTest

/// PROTOTYPE (#269) — THROWAWAY capture driver, **not** a behavioral test. It
/// asserts almost nothing; its output is the frames the ADR argues from.
///
/// Only the *flip* is driven from here. The static docked/palette pairs are shot
/// with `simctl launch` + `simctl io screenshot` instead (see the branch's
/// `palette-report/`), because XCUITest has to raise the **software keyboard** in
/// order to type a query — the exact condition palette mode is defined by the
/// absence of. A driver that types can never photograph the mode it is trying to
/// photograph. So nothing here types: the query arrives via
/// `-palette-seed-query`, and the only key pressed is the `⌘⇧P` that flips modes.
///
/// Frames are written with `NSTemporaryDirectory()`, which lands inside the
/// runner's sandbox on the simulator — `TEST_RUNNER_SCREENSHOT_DIR` does not
/// reach it — so the caller harvests them from the app container afterwards.
final class PalettePrototypeCaptureTests: XCTestCase {

    private var shotDir: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: shotDir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
    }

    /// Frames straight through the mode change, at the real motion budget.
    ///
    /// Tapping the hidden `palette-flip` target stands in for the keyboard being
    /// attached — the cause a test cannot produce (`GCKeyboard` never reports one
    /// in the simulator), whose *effect* is the whole motion question. A **tap**,
    /// not a key press: sending a key makes XCUITest raise the software keyboard,
    /// which both breaks the mode's precondition and swamps the pixel diff with a
    /// keyboard animation. The shots run back to back with no sleep, so the series
    /// samples the transition rather than its endpoints.
    @MainActor
    func testCaptureFlipTimeLapse() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-reset-folders",
            "-uitest-seed-files",
            "-uitest-stub-reminders",
            "-uitest-pin-favorite", "builtin.settings",
            "-palette-prototype",
            "-palette-badge",
            "-palette-force-hardware-keyboard",
            // Flip every 4s, forever — no tap, no key, nothing the layout can
            // intercept. The burst below simply films straight through it.
            "-palette-auto-flip", "4",
            "-palette-seed-query", "se",
            // Deliberately no `-uitest-instant-motion`: the motion budget is the
            // subject of this run, so collapsing it would answer nothing.
        ]
        app.launch()

        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 30))
        sleep(3)
        snap("flip-00-before")

        // One long continuous burst across several flips, so both directions are
        // filmed and no frame is spent waiting for a gesture to be delivered.
        for frame in 1...90 { snap(String(format: "flip-%03d", frame)) }
    }
}
