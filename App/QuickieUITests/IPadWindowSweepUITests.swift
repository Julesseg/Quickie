import XCTest

/// Throwaway QA driver for issue #268's odd-size sweep. Not a gate and not part of the
/// suite's contract: it resizes the app's iPadOS 26 window to each tile size in turn and
/// holds there long enough for a host-side `simctl io screenshot` loop to catch it.
///
/// Skipped unless `QUICKIE_WINDOW_SWEEP=1` is in the environment, so CI never runs it:
/// it drags SpringBoard's window chrome, which exists on an iPad in Windowed Apps mode
/// and nowhere else, and a QA sweep is evidence rather than a gate. Run it with
/// `-only-testing:QuickieUITests/IPadWindowSweepUITests` and that variable set.
final class IPadWindowSweepUITests: XCTestCase {

    /// The resize handle sits this far in from the window's bottom-right corner.
    private let handleInset = CGVector(dx: 30, dy: 42)

    /// How long to hold at each size, so the host loop catches at least one frame of it.
    private let hold: TimeInterval = 6

    @MainActor
    func testSweepThroughTheSystemTileSizes() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["QUICKIE_WINDOW_SWEEP"] == "1",
            "the window sweep is a QA driver, not a gate — set QUICKIE_WINDOW_SWEEP=1 to run it"
        )

        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 30))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let display = springboard.frame.size
        var window = app.frame.size
        Thread.sleep(forTimeInterval: hold)

        // The tiles the sweep walks, as window sizes. A window is a free rectangle under
        // iPadOS 26, so each is produced by dragging rather than by snapping — the point
        // is the size the layout is handed, not the gesture that produced it. The last
        // one is below the declared floor on purpose: the window should refuse it.
        let sizes: [CGSize] = [
            CGSize(width: display.width * 2 / 3, height: display.height),
            CGSize(width: display.width / 2, height: display.height),
            CGSize(width: display.width / 3, height: display.height),
            CGSize(width: 320, height: display.height),
            CGSize(width: display.width / 2, height: display.height / 2),
            CGSize(width: display.width, height: 480),
            CGSize(width: 200, height: 200),
        ]

        for size in sizes {
            let from = springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.width - handleInset.dx,
                                     dy: window.height - handleInset.dy))
            let to = springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: size.width - handleInset.dx,
                                     dy: size.height - handleInset.dy))
            from.press(forDuration: 0.8, thenDragTo: to)
            Thread.sleep(forTimeInterval: hold)
            window = app.frame.size
            XCTContext.runActivity(named: "window is now \(window)") { _ in }
        }
    }
}
