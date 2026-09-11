import XCTest
import UIKit

/// Home keeps its Favorites on screen when the keyboard leaves it little room.
///
/// In a landscape iPad the docked keyboard leaves ~370pt above it. The launcher
/// lifts its bar by hand (issue #58, ADR 0040), and its minimum height (the
/// Favorites grid, the bar and the held keyboard inset) used to be measured
/// against that shortened height. It didn't fit, SwiftUI centred the overflow,
/// and the grid slid ~120pt up, half off the top of the screen, whenever the
/// keyboard came up.
///
/// Portrait never showed it, because there is room to spare above the keyboard,
/// so the test turns the device first.
final class HomeUnderKeyboardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testFavoritesStayOnScreenWithTheKeyboardUpInLandscape() throws {
        // A landscape iPhone still loses the grid's top row, for a second reason:
        // the keyboard leaves ~175pt, less than the window's 320pt floor
        // (`LauncherWindow.minimumSize`, ADR 0041), and that floor frame overflows
        // and is centred the same way. It is applied outside the NavigationStack,
        // so this fix doesn't reach it.
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "a landscape iPhone's keyboard leaves less height than the window floor (ADR 0041)"
        )
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "-uitest-reset-signals", "-uitest-instant-motion",
            "-uitest-pin-favorite", "builtin.settings",
            "-uitest-pin-favorite", "builtin.new-reminder",
            "-uitest-pin-favorite", "builtin.new-event",
        ]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "tapping the input brings the keyboard up")
        // Let it finish rising, and the bar with it.
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let card = app.buttons["favorite.builtin.settings"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the pinned Favorites render on Home")
        XCTAssertGreaterThanOrEqual(
            card.frame.minY, app.frame.minY,
            "the first Favorite card slid off the top of the screen with the keyboard up "
                + "(its top is at \(card.frame.minY)pt)"
        )
        XCTAssertTrue(card.isHittable, "the first Favorite card should still be tappable")

        // The fix must not buy the grid its room by dropping the bar: the input still
        // rides the keyboard. Only asserted with a real software keyboard; a
        // hardware keyboard's shortcuts bar lifts nothing worth measuring.
        if keyboard.keys.count >= 10 {
            XCTAssertLessThanOrEqual(
                input.frame.maxY, keyboard.frame.minY,
                "the input bar should sit above the keyboard, not behind it"
            )
        }
    }
}
