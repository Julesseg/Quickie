import XCTest

/// The trailing clear button inside the input's Liquid Glass capsule
/// (CONTEXT.md → Clear button). Only the real field on a simulator can prove
/// these, since they all hang off the live query binding and the software
/// keyboard:
///
/// 1. It is **offered only when there is something to clear** — absent on the
///    empty-query Home, present the moment a character is typed.
/// 2. Tapping it **empties the query** and drops the app back to Home.
/// 3. Clearing **keeps the keyboard up** — clearing is "start over", not "done".
final class InputClearUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Clean signals slate so persisted Favorites/Frecency can't change which
        // rows appear (mirrors the other UI suites).
        app.launchArguments += ["-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// The button is furniture of a *non-empty* query: Home (empty query) shows no
    /// clear affordance, and the first keystroke brings it in.
    @MainActor
    func testClearButtonIsOfferedOnlyWhileTheQueryIsNonEmpty() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")

        let clear = app.buttons["clear-input"]
        XCTAssertFalse(
            clear.exists,
            "the empty-query Home has nothing to clear, so no clear button is offered"
        )

        input.tap()
        input.typeText("settings")

        XCTAssertTrue(
            clear.waitForExistence(timeout: 5),
            "typing offers the clear button inside the input"
        )
    }

    /// Tapping it empties the query: the results it surfaced go, Home comes back,
    /// and the button retires with the text that justified it.
    @MainActor
    func testTappingClearEmptiesTheQueryAndReturnsToHome() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        input.typeText("settings")

        // The always-present Settings command row is the proof a query is live.
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
            "typing 'settings' surfaces the Settings command row"
        )

        let clear = app.buttons["clear-input"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "the clear button is offered on a typed query")
        clear.tap()

        // The query is gone: the result it surfaced goes with it, and the button
        // withdraws — its visibility *is* "the query is non-empty".
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForNonExistence(timeout: 10),
            "clearing the query takes its results with it"
        )
        XCTAssertTrue(
            clear.waitForNonExistence(timeout: 5),
            "with nothing left to clear the button withdraws"
        )
        // An emptied field reports either nothing or its placeholder — never the
        // text that was typed.
        let value = input.value as? String ?? ""
        XCTAssertFalse(
            value.contains("settings"),
            "the typed text is gone from the field (value: \(value))"
        )
    }

    /// Clearing is "start over", not "done": the keyboard stays up so the next
    /// query can be typed straight away, with no tap back into the field.
    @MainActor
    func testClearingKeepsTheKeyboardUp() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        input.typeText("settings")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "typing brings the keyboard up")

        app.buttons["clear-input"].tap()

        XCTAssertTrue(
            app.keyboards.firstMatch.exists,
            "clearing leaves the keyboard up — the next query is typed, not tapped into"
        )
        // And the emptied field really is still live: typing lands in it without
        // tapping back. Typed at the *app* (not the element), so the keystrokes go
        // wherever focus actually is — the point under test — rather than XCTest
        // quietly restoring focus for us.
        app.typeText("settings")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "the field keeps focus through a clear, so the next keystrokes land in it"
        )
    }
}
