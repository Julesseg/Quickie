// PROTOTYPE — THROWAWAY. Captures comparison screenshots of the three
// color-picker variants (see PrototypeColorPickerVariants.swift). Delete with
// the prototype.
import XCTest

final class PrototypeScreenshotTests: XCTestCase {

    @MainActor
    func testCaptureColorPickerVariantScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()

        // Reach a fresh editor with a realistic action typed in.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("custom actions")
        let command = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()
        let add = app.buttons["add-custom-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let name = app.textFields["custom-action-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Add to Things")
        let url = app.textFields["custom-action-url-field"]
        url.tap()
        url.typeText("things:///add?title={title}")

        // Dismiss the keyboard so the symbol/color section is on screen.
        app.swipeUp()

        let next = app.buttons["prototype-variant-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "the prototype pill is present in DEBUG builds")

        // Normalize to variant A (the pill persists across runs): press next up
        // to three times until the inline strip's Blue dot is visible.
        var hops = 0
        while !app.buttons["Blue"].exists && hops < 3 {
            next.tap()
            hops += 1
        }
        XCTAssertTrue(app.buttons["Blue"].waitForExistence(timeout: 3), "variant A shows the inline strip")

        // Variant A — inline strip, with Blue chosen so selection state shows.
        app.buttons["Blue"].tap()
        shoot(app, "variant-A-inline-strip")

        // Variant B — live preview page: switch, push the Color row, pick Pink.
        next.tap()
        let colorRow = app.buttons["custom-action-color-row"]
        XCTAssertTrue(colorRow.waitForExistence(timeout: 5))
        colorRow.tap()
        let pink = app.buttons["Pink"]
        XCTAssertTrue(pink.waitForExistence(timeout: 5), "variant B shows the swatch circles")
        pink.tap()
        shoot(app, "variant-B-live-preview")
        app.navigationBars.buttons.firstMatch.tap()

        // Variant C — badge list: switch, push, screenshot (no tap — it pops).
        next.tap()
        XCTAssertTrue(colorRow.waitForExistence(timeout: 5))
        colorRow.tap()
        XCTAssertTrue(app.buttons["Teal"].waitForExistence(timeout: 5), "variant C lists the badges")
        shoot(app, "variant-C-badge-list")
    }

    @MainActor
    private func shoot(_ app: XCUIApplication, _ named: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = named
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
