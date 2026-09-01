import XCTest

/// PROTOTYPE (#269) — THROWAWAY capture driver, **not** a behavioral test. It
/// asserts almost nothing; its output is the PNGs the ADR argues from.
///
/// Writes full-screen PNGs to the host directory named by `SCREENSHOT_DIR` (pass
/// it as `TEST_RUNNER_SCREENSHOT_DIR` on the `xcodebuild` invocation), following
/// the iPad UI audit's driver. Every step is guarded so a missing element skips
/// a shot instead of aborting the walk.
///
/// Three jobs:
/// - `testCaptureDockedLayout` / `testCapturePaletteLayout` — the same states in
///   each mode, pinned, so the pairs are directly comparable.
/// - `testCaptureRealTrigger` — no pin: whatever the *real* condition resolves
///   to on this simulator, badge visible, which is what proves the trigger.
/// - `testCaptureFlipTimeLapse` — frames through the mode change itself, for the
///   motion-budget question.
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

    /// A launcher seeded the same way for every run, so two shots differ only by
    /// the thing being compared.
    private func launch(_ extra: [String], instantMotion: Bool = true) -> XCUIApplication {
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
        ]
        // The flip's motion is the *subject* of the time-lapse, so that run must
        // not collapse the budget to nothing.
        if instantMotion { app.launchArguments.append("-uitest-instant-motion") }
        app.launchArguments += extra
        app.launch()
        return app
    }

    private func search(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields["search-input"]
        guard input.waitForExistence(timeout: 10) else { return }
        let clear = app.buttons["clear-input"]
        if clear.exists { clear.tap() }
        input.tap()
        input.typeText(text)
    }

    /// The states the two layouts are judged on: an empty Home, a ranked list
    /// (the rank-0 adjacency question), a single calculator result, and a
    /// multi-step capture (whose bar replaces the input entirely).
    private func walk(_ app: XCUIApplication, prefix: String) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        sleep(2)
        snap("\(prefix)-10-home")

        search(app, "se")
        sleep(1)
        snap("\(prefix)-11-results-ranked")

        search(app, "2+2")
        sleep(1)
        snap("\(prefix)-12-results-calc")

        search(app, "remind")
        sleep(1)
        let remind = app.buttons["builtin.new-reminder"].firstMatch
        if remind.waitForExistence(timeout: 5) {
            remind.tap()
            sleep(2)
            snap("\(prefix)-13-capture")
        }
    }

    @MainActor
    func testCaptureDockedLayout() throws {
        walk(launch(["-palette-mode", "docked"]), prefix: "docked")
    }

    @MainActor
    func testCapturePaletteLayout() throws {
        walk(launch(["-palette-mode", "palette"]), prefix: "palette")
    }

    /// No pin: the badge reports the size class and the keyboard kind this
    /// simulator actually presents, and the layout is whatever the trigger makes
    /// of them. Run once with the simulator's hardware keyboard connected and
    /// once without, and the pair *is* the trigger's evidence.
    @MainActor
    func testCaptureRealTrigger() throws {
        let app = launch([])
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        sleep(2)
        snap("trigger-00-launch")
        search(app, "se")
        sleep(2)
        snap("trigger-01-results")
    }

    /// Frames straight through the mode change. `⌘⇧P` stands in for the keyboard
    /// being attached — the cause a UI test cannot produce, whose *effect* is the
    /// whole motion question — and the shots run back to back with no sleep, so
    /// the series samples the transition rather than its endpoints.
    @MainActor
    func testCaptureFlipTimeLapse() throws {
        let app = launch(["-palette-manual-flip"], instantMotion: false)
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        sleep(2)
        search(app, "se")
        sleep(2)
        snap("flip-00-before")

        app.typeKey("p", modifierFlags: [.command, .shift])
        for frame in 1...24 {
            snap(String(format: "flip-%02d", frame))
        }
        sleep(2)
        snap("flip-99-after")

        // …and back, so the return trip is filmed too: a mode change that only
        // looks calm in one direction has not answered the question.
        app.typeKey("p", modifierFlags: [.command, .shift])
        for frame in 1...24 {
            snap(String(format: "unflip-%02d", frame))
        }
        sleep(2)
        snap("unflip-99-after")
    }
}
