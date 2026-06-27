import XCTest

/// The UI-only acceptance criteria for Snippets (issue #6) that can only be
/// verified by driving the real app on a simulator: a snippet created in the
/// library persists, surfaces as a searchable Result row, and its main action
/// copies — confirmed by a lightweight banner. The copy-out *logic* (run →
/// .copyText(body)) is covered deterministically by QuickieCore's SnippetTests;
/// these prove the SwiftData + UI wiring around it.
final class SnippetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Create a snippet through the library editor, then find it by typing and
    /// run it — proving create → persist → index → search → copy end to end.
    @MainActor
    func testCreateSnippetThenSearchAndCopy() throws {
        let app = launchApp()

        // Open the Snippet library and compose a new snippet.
        app.buttons["open-snippets"].tap()
        XCTAssertTrue(app.buttons["snippet-add"].waitForExistence(timeout: 10))
        app.buttons["snippet-add"].tap()

        let title = "Quickie Greeting"
        let titleField = app.textFields["snippet-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)

        let bodyField = app.textFields["snippet-body-field"]
        bodyField.tap()
        bodyField.typeText("Hello from Quickie")

        app.buttons["snippet-save"].tap()

        // Back in the library, dismiss to the input.
        app.buttons["Done"].tap()

        // Type to search — the snippet surfaces as a ranked Result row.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("greeting")

        // A result row is a Button whose label is the snippet title; its
        // identifier is a store-derived hash, so match on the label. (The inner
        // Text is merged into the Button's accessibility element, so it is not
        // independently queryable as a staticText — mirror the built-in tests,
        // which find rows by the button, not the text.)
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved snippet should appear as a searchable result")

        // Running its main action copies, acknowledged by the confirmation banner.
        row.tap()
        XCTAssertTrue(
            app.staticTexts["copy-confirmation"].waitForExistence(timeout: 5),
            "running a snippet's main action should copy and show a lightweight confirmation"
        )
    }
}
