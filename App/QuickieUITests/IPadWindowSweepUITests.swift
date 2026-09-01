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
        let floor = CGSize(width: 320, height: 320)

        for size in sizes {
            // Both ends of the drag are measured from the *window*, not the display: a
            // window under iPadOS 26 is not anchored at the display's origin, so a grab
            // computed from the screen misses the handle entirely and the sweep would
            // green-run having resized nothing.
            let window = app.frame
            let handle = springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.maxX - handleInset.dx,
                                     dy: window.maxY - handleInset.dy))
            let target = springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.minX + size.width - handleInset.dx,
                                     dy: window.minY + size.height - handleInset.dy))
            handle.press(forDuration: 0.8, thenDragTo: target)
            Thread.sleep(forTimeInterval: hold)

            // The window should have landed at the asked-for size, or — for the last,
            // deliberately-too-small one — at the declared floor and no smaller. Loose
            // tolerances: the system snaps and rounds, and this is a driver for the eye
            // rather than a gate. What it must *not* do is silently resize nothing.
            let got = app.frame.size
            XCTAssertEqual(got.width, max(size.width, floor.width), accuracy: 24,
                           "the window should have resized to \(size), and is \(got)")
            XCTAssertEqual(got.height, max(size.height, floor.height), accuracy: 24,
                           "the window should have resized to \(size), and is \(got)")
            XCTContext.runActivity(named: "window is now \(got)") { _ in }
        }
    }
}
