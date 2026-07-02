import XCTest

/// The UI-only acceptance criteria for **secondary actions** (issue #58,
/// CONTEXT.md → Secondary action; ADR 0017) that can only be verified by driving
/// the real app on a simulator: long-pressing a result shows **one** menu that
/// combines the row's eligible content verbs (Copy / Share / Reveal in Files)
/// with the existing Pin/Unpin item, and a content-less row (a command) shows
/// only Pin/Unpin — no dead verbs. A Pile entry is the content-bearing row
/// exercised here (its content is its saved text).
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
        // A clean in-memory store so a Pile entry captured here can't collide
        // with a stale row from a previous run.
        app.launchArguments = ["--uitesting"]
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// Save a query to the Pile, then long-press its row: the menu offers
    /// **Copy** and **Share** (act on a Pile entry — its content is its text),
    /// alongside the Pin item.
    @MainActor
    func testLongPressingAPileEntryOffersCopyAndShare() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        let thought = "Buy milk and eggs"
        input.typeText(thought)

        // Capture it silently through the always-present "Save for later"
        // Fallback — no editor, no confirm.
        let saveForLater = app.buttons["builtin.save-for-later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 5))
        saveForLater.tap()

        // Search it back up by body text and long-press the row for its menu.
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
                      "a Pile entry's long-press menu should offer Copy (its text)")
        XCTAssertTrue(app.buttons["Share"].exists,
                      "a Pile entry's long-press menu should offer Share")
        XCTAssertTrue(app.buttons["Pin as Favorite"].exists,
                      "the content verbs join the existing Pin item in one menu")
        // A Pile entry carries no file, so Reveal in Files must not appear (no
        // dead item).
        XCTAssertFalse(app.buttons["Reveal in Files"].exists,
                       "a non-file row must not offer Reveal in Files")
    }

    /// Compose a snippet, then long-press its result row: the menu offers **Edit**
    /// (open the stored record in the editor) on top of Copy and Share — the verb a
    /// stored, titled Snippet earns that a bare text row does not (ADR 0017).
    @MainActor
    func testLongPressingASnippetOffersEdit() throws {
        let app = launchApp()

        // Compose a snippet from the input via the always-present "New Snippet"
        // Fallback, then name and save it.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("221B Baker Street")

        let newSnippet = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New Snippet")
        ).firstMatch
        XCTAssertTrue(newSnippet.waitForExistence(timeout: 5))
        newSnippet.tap()

        let title = "Home address"
        let bodyField = app.textFields["snippet-body-field"]
        XCTAssertTrue(bodyField.waitForExistence(timeout: 10))
        app.textFields["snippet-title-field"].tap()
        app.textFields["snippet-title-field"].typeText(title)
        app.buttons["snippet-save"].tap()

        // Search it back up by title and long-press the row for its menu.
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(title)
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.3)

        // Edit joins the universal Copy / Share and the existing Pin item.
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5),
                      "a snippet's long-press menu should offer Edit (open its editor)")
        XCTAssertTrue(app.buttons["Copy"].exists,
                      "a snippet's long-press menu should still offer Copy")
        XCTAssertTrue(app.buttons["Share"].exists,
                      "a snippet's long-press menu should still offer Share")
        XCTAssertTrue(app.buttons["Pin as Favorite"].exists,
                      "the content verbs join the existing Pin item in one menu")
        XCTAssertFalse(app.buttons["Reveal in Files"].exists,
                       "a non-file row must not offer Reveal in Files")
    }

    /// A Shortcut row long-press offers **Edit** — a deeplink into the Shortcuts
    /// app's editor by name — and, being a launchable reference with no text, it
    /// offers neither Copy nor Share (ADR 0017). A Shortcut Action can only be
    /// registered by the Sync-Shortcut import (names-only), so the row is seeded
    /// through the real ingest via `-uitest-seed-shortcuts`.
    @MainActor
    func testLongPressingAShortcutOffersEditOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-instant-motion"]
        // Seed one imported Shortcut through the real ingest so its row is searchable
        // without a device round-trip through the Shortcuts app.
        app.launchArguments += ["-uitest-seed-shortcuts", Self.seededShortcutName]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText(Self.seededShortcutName)

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", Self.seededShortcutName)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.3)

        // Edit is offered (open the shortcut in the Shortcuts app), alongside Pin.
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5),
                      "a shortcut's long-press menu should offer Edit (open it in Shortcuts)")
        XCTAssertTrue(app.buttons["Pin as Favorite"].exists,
                      "Edit joins the existing Pin item in one menu")
        // A Shortcut is a launchable reference, not a value: no text to copy/share.
        XCTAssertFalse(app.buttons["Copy"].exists,
                       "a shortcut has no text, so it must not offer Copy")
        XCTAssertFalse(app.buttons["Share"].exists,
                       "a shortcut has no text, so it must not offer Share")
        XCTAssertFalse(app.buttons["Reveal in Files"].exists,
                       "a non-file row must not offer Reveal in Files")
    }

    /// The name of the Shortcut Action seeded through the real import path so a
    /// shortcut row is searchable in this suite.
    private static let seededShortcutName = "UITest Shortcut"

    /// A command row carries no content, so its long-press menu shows only
    /// Pin/Unpin — exactly as before secondary actions existed (AC
    /// "command/capture rows show only Pin/Unpin").
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
