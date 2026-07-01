import XCTest

/// The UI-only acceptance criteria for **secondary actions** (issue #58,
/// CONTEXT.md → Secondary action; ADR 0017) that can only be verified by driving
/// the real app on a simulator: long-pressing a result shows **one** menu that
/// combines the row's eligible content verbs (Copy / Share / Reveal in Files)
/// with the existing Pin/Unpin item, and a content-less row (a command) shows
/// only Pin/Unpin — no dead verbs.
///
/// Eligibility itself is a pure function of `ResultContent`, covered
/// deterministically by QuickieCore's SecondaryActionTests / ResultContentTests;
/// these prove the menu is wired to it. We assert the menu *items exist* rather
/// than firing them: XCUITest can surface a SwiftUI context-menu item in the
/// simulator but cannot run its action (the menu is a separate remote view), so
/// the item's execution is exercised at the App edge and verified on device.
final class SecondaryActionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A clean in-memory store so a note captured here can't collide with a
        // stale row from a previous run.
        app.launchArguments = ["--uitesting"]
        app.launch()
        return app
    }

    /// Capture a Note, then long-press it: its menu offers **Copy** and **Share**
    /// (act on a Note — AC "long-pressing a Note offers Copy (its body) and
    /// Share"), alongside the Pin item.
    @MainActor
    func testLongPressingANoteOffersCopyAndShare() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Buy milk and eggs"
        input.typeText(thought)

        // Capture it through the always-present "New Note" Fallback.
        let newNote = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New Note")
        ).firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        newNote.tap()
        XCTAssertTrue(app.textFields["note-body-field"].waitForExistence(timeout: 10))
        app.buttons["note-save"].tap()

        // Search it back up and long-press the row to reveal its menu.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(thought)
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.3)

        // The content verbs and the pin item share one menu.
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5),
                      "a Note's long-press menu should offer Copy (its body)")
        XCTAssertTrue(app.buttons["Share"].exists,
                      "a Note's long-press menu should offer Share")
        XCTAssertTrue(app.buttons["Pin as Favorite"].exists,
                      "the content verbs join the existing Pin item in one menu")
        // A Note carries no file, so Reveal in Files must not appear (no dead item).
        XCTAssertFalse(app.buttons["Reveal in Files"].exists,
                       "a non-file row must not offer Reveal in Files")
    }

    /// A command row carries no content, so its long-press menu shows only
    /// Pin/Unpin — exactly as before secondary actions existed (AC
    /// "command/capture/shortcut rows show only Pin/Unpin").
    @MainActor
    func testLongPressingACommandRowOffersOnlyPin() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("settings")

        let settings = app.buttons["builtin.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.press(forDuration: 1.3)

        // Pin is offered; the content verbs are not — a command has no content.
        XCTAssertTrue(app.buttons["Pin as Favorite"].waitForExistence(timeout: 5),
                      "a command row still offers Pin as Favorite")
        XCTAssertFalse(app.buttons["Copy"].exists,
                       "a content-less command row must not offer Copy")
        XCTAssertFalse(app.buttons["Share"].exists,
                       "a content-less command row must not offer Share")
    }
}
