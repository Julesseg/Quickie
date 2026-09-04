// PROTOTYPE (#286) — THROWAWAY. Photographs a row's long-press menu on the
// winning candidates so the verdict can say whether the plain in-place
// highlight reads on a non-glass row (the lifted preview only exists because
// it did not read on glass). Delete with the prototype.
import XCTest

final class PrototypeLongPressTests: XCTestCase {
    @MainActor
    func testLongPressOnFlatRingRows() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "-uitest-reset-signals", "-uitest-instant-motion",
            "-proto-row", "flat", "-proto-hero", "ring", "-proto-no-badge", "-proto-seed-query", "se", "-proto-plain-menu",
        ]
        app.launch()
        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Pin as Favorite"].waitForExistence(timeout: 5))
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "long-press-flat-ring-plain"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
