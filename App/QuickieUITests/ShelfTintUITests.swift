import XCTest
import UIKit

/// The **Shelf** button's glass carries its action's **Action color** (CONTEXT.md →
/// Shelf, Action color; ADR 0037; issue #244) — the acceptance criterion no other test
/// can hold, because it is a property of what the row *looks like* rather than of what
/// it does or which elements exist.
///
/// Every assertion here is **relative**: which channel dominates a button's glass, and
/// how two buttons in the same frame compare. Nothing pins an absolute value. That is
/// deliberate — the tint is held back to a fraction of the hue (`FallbackShelfRow`),
/// laid over a live, blurred backdrop (ADR 0034) whose exact pixels depend on the
/// appearance, the device, and what is behind the bar. What must never drift is the
/// *ordering*: a green-tokened action's button is greener than red, a red-tokened one
/// redder than green, and recolouring an action moves its button with it. Those hold on
/// any backdrop and in either appearance, which is what makes them safe to gate CI on.
///
/// The wiring these ride on (which members show, what a tap does) is `ShelfRowUITests`;
/// the palette's own legibility is measured in QuickieCore's `ActionColorTests`.
final class ShelfTintUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    // MARK: - Sampling a button's glass

    /// The average colour of a Shelf button's **ring** — the band of glass between the
    /// glyph and the circle's edge.
    ///
    /// A ring rather than the whole circle because the glyph in the middle is drawn
    /// `.primary` (black or white, never the hue), so including it would drag every
    /// sample toward the appearance and away from the tint under test. The band stops
    /// short of the edge for the same reason in reverse: the glass's specular rim is the
    /// backdrop showing through, not the tint.
    @MainActor
    private func ringColor(of element: XCUIElement) -> (red: Double, green: Double, blue: Double) {
        let screenshot = XCUIScreen.main.screenshot().image
        guard let cgImage = screenshot.cgImage else {
            XCTFail("the screen produced no bitmap to sample")
            return (0, 0, 0)
        }
        // The screenshot is in pixels, the element's frame in points.
        let scale = screenshot.scale
        let frame = element.frame
        let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                          width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = cgImage.cropping(to: rect) else {
            XCTFail("the button's frame (\(frame)) is not inside the screen bitmap")
            return (0, 0, 0)
        }

        let width = crop.width, height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let centerX = Double(width) / 2, centerY = Double(height) / 2
        let radius = min(centerX, centerY)
        var totals = (red: 0.0, green: 0.0, blue: 0.0)
        var counted = 0
        for y in 0..<height {
            for x in 0..<width {
                let distance = ((Double(x) - centerX) * (Double(x) - centerX)
                    + (Double(y) - centerY) * (Double(y) - centerY)).squareRoot()
                guard distance > radius * 0.55, distance < radius * 0.92 else { continue }
                let offset = (y * width + x) * 4
                totals.red += Double(pixels[offset])
                totals.green += Double(pixels[offset + 1])
                totals.blue += Double(pixels[offset + 2])
                counted += 1
            }
        }
        guard counted > 0 else {
            XCTFail("the button sampled to nothing — is it on screen?")
            return (0, 0, 0)
        }
        return (totals.red / Double(counted), totals.green / Double(counted), totals.blue / Double(counted))
    }

    // MARK: - Driving the Shelf

    /// Promotes each named fallback onto the Shelf through the real page — the only way
    /// a member gets there — in one visit, then returns to the launcher.
    @MainActor
    private func shelve(_ app: XCUIApplication, titles: [String]) {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 10), "typing 'fallbacks' surfaces its command row")
        command.tap()

        for title in titles {
            // The page is three sections tall and CI runs on an iPhone SE, so walk the
            // row into the render tree both ways — the idiom the other Shelf suites use.
            let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
            for _ in 0..<4 where !row.exists { app.swipeDown() }
            for _ in 0..<6 where !row.exists { app.swipeUp() }
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(title) is listed on the Fallbacks page")
            let shelfButton = row.buttons["Move to the shelf"]
            XCTAssertTrue(shelfButton.waitForExistence(timeout: 5), "\(title) carries the shelf button")
            shelfButton.tap()
        }

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the launcher input is back")
    }

    /// Types a query so the Shelf comes up, and waits for the named button.
    @MainActor
    private func showShelf(_ app: XCUIApplication, query: String, awaiting identifier: String) -> XCUIElement {
        let input = app.textFields["search-input"]
        input.tap()
        input.typeText(query)
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "a typed query brings the Shelf up")
        return button
    }

    // MARK: - The criteria

    /// A member's button is tinted by its **Action color token**, not by its provider
    /// kind: Google Maps ships green and YouTube ships red (`CatalogSeed`), and both are
    /// `customAction`s — the *same* kind, so a kind-derived row would paint these two
    /// buttons identically. Their hues separating is the whole criterion.
    @MainActor
    func testShelfButtonGlassCarriesTheActionColorToken() throws {
        let app = launchApp()
        shelve(app, titles: ["Google Maps", "YouTube"])

        let maps = showShelf(app, query: "paris", awaiting: "shelf.seed.google-maps")
        let youTube = app.buttons["shelf.seed.youtube"]
        XCTAssertTrue(youTube.waitForExistence(timeout: 10), "both shelved members are up")

        let green = ringColor(of: maps)
        let red = ringColor(of: youTube)

        XCTAssertGreaterThan(green.green, green.red,
                             "the green-tokened action's glass leans green, not toward its kind's hue")
        XCTAssertGreaterThan(red.red, red.green,
                             "the red-tokened action's glass leans red")
        // Cross-compared in the same frame, so one shared backdrop cannot explain both.
        XCTAssertGreaterThan(green.green - green.red, red.green - red.red,
                             "two members of the same kind are told apart by their tokens")
    }

    /// **Default** is the absence of a token, and it must still tint: an action with no
    /// chosen colour falls back to its kind's hue rather than to plain, untinted glass —
    /// the half of the rule a token-only implementation would quietly drop.
    ///
    /// An imported **Shortcut** is the subject because it is now the only shelvable
    /// action that ships no token: the seeds, the Catalog, and the four built-in
    /// captures all state one (issue #244). Its kind hue is the Shortcut magenta.
    ///
    /// Measured **against a green-tokened member in the same frame**, not against a
    /// fixed threshold. The backdrop behind the row is itself lavender (ADR 0034), so a
    /// button drawn with no tint at all would already sample red-over-green — an
    /// absolute assertion here would pass with the tint deleted, which is precisely the
    /// regression this test exists to catch.
    @MainActor
    func testDefaultFallsBackToTheKindDerivedTint() throws {
        // Seeded `acceptsInput` on, which is what makes a Shortcut fallback-eligible
        // and therefore shelvable at all.
        let app = launchApp(["-uitest-seed-input-shortcuts", "Timer"])
        shelve(app, titles: ["Timer", "Google Maps"])

        let timer = showShelf(app, query: "dentist", awaiting: "shelf.shortcut.timer")
        let maps = app.buttons["shelf.seed.google-maps"]
        XCTAssertTrue(maps.waitForExistence(timeout: 10), "both shelved members are up")

        let magenta = ringColor(of: timer)
        let green = ringColor(of: maps)

        XCTAssertGreaterThan(magenta.red - magenta.green, green.red - green.green,
                             "an action with no chosen colour still wears its kind's hue")
        XCTAssertGreaterThan(magenta.blue - magenta.green, green.blue - green.green,
                             "…and that hue is the kind's magenta, not the backdrop showing through")
    }

    /// Recolouring an action moves its Shelf button with it — the Shelf reads the live
    /// action rather than a value snapshotted when the row was built. Maps goes green →
    /// purple in the editor, and its button must follow: purple is blue-dominant where
    /// green is green-dominant, so the two channels swap places.
    @MainActor
    func testRecolouringAnActionRetintsItsShelfButton() throws {
        let app = launchApp()
        shelve(app, titles: ["Google Maps"])

        let before = ringColor(of: showShelf(app, query: "paris", awaiting: "shelf.seed.google-maps"))
        XCTAssertGreaterThan(before.green, before.blue, "Maps ships green")

        // Clear the query so the launcher is back at Home before typing the page's name.
        let input = app.textFields["search-input"]
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "paris".count))
        input.typeText("custom actions")
        let page = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), "typing 'custom actions' surfaces its command row")
        page.tap()

        let maps = app.staticTexts["Google Maps"]
        var scrolls = 0
        while !maps.exists && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        XCTAssertTrue(maps.waitForExistence(timeout: 10), "the seeded Maps action is listed")
        maps.tap()

        let appearance = app.buttons["custom-action-appearance-row"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10), "the editor offers the Symbol & Color row")
        appearance.tap()
        let purple = app.buttons["action-color-option.purple"]
        XCTAssertTrue(purple.waitForExistence(timeout: 10))
        purple.tap()
        // The appearance page's own Back, then Save on the editor sheet.
        app.navigationBars["Symbol & Color"].buttons.firstMatch.tap()
        let save = app.buttons["save-custom-action"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()

        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) { back.tap() }
        XCTAssertTrue(input.waitForExistence(timeout: 15), "the launcher is back")

        let after = ringColor(of: showShelf(app, query: "paris", awaiting: "shelf.seed.google-maps"))
        XCTAssertGreaterThan(after.blue, after.green,
                             "the recoloured action's button is purple now, not green")
        XCTAssertGreaterThan(after.blue - after.green, before.blue - before.green,
                             "…and it moved because of the edit, on the same backdrop as before")
    }
}
