import XCTest

/// UI-only acceptance for the wrap-and-grow search input (issue #63) — the parts
/// that can only be proven by driving the real field on a simulator, since they
/// depend on the exact `TextField(axis: .vertical)` behavior:
///
/// 1. Typing past one line **wraps and grows** the field (its height increases).
/// 2. The software keyboard's **Return still runs the highlighted result** rather
///    than inserting a literal newline — the newline-interception in `InputBar`
///    that turns a lone trailing `"\n"` back into the highlighted result's Enter.
///
/// The capsule↔box threshold math itself is covered purely in QuickieCore's
/// `InputBarGrowthTests`; this is the end-to-end App behavior on top of it.
final class InputWrapUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// Typing enough text to overflow one line wraps it and grows the field taller,
    /// rather than scrolling sideways on a single line (issue #63 AC #1). We assert
    /// the field's height increases — the observable proof it grew upward.
    @MainActor
    func testTypingPastOneLineGrowsTheField() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")

        // Height while still on a single line (empty, just the placeholder).
        let singleLineHeight = input.frame.height

        // Enough words to spill well past one line at the field's width. Spaces let
        // it wrap by word; autocorrect is disabled so nothing rewrites the text.
        input.tap()
        input.typeText("the quick brown fox jumps over the lazy dog and then keeps on running well past one line")

        // The field is now taller than it was on a single line — it wrapped and grew.
        let grownHeight = input.frame.height
        XCTAssertGreaterThan(
            grownHeight, singleLineHeight + 10,
            "typing past one line should wrap and grow the field taller, not scroll on one line"
        )
    }

    /// Pressing Return on the (now vertical-axis) field runs the highlighted result
    /// instead of inserting a newline (issue #63 — CONTEXT.md → Highlighted result).
    /// We type "settings" so the always-present Settings command is the top match,
    /// press Return, and assert its page pushed — proof the newline was intercepted
    /// as Enter. (Settings is a built-in command row, so it is reliably present.)
    @MainActor
    func testReturnRunsHighlightedResultOnVerticalField() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        input.typeText("settings")

        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
            "typing 'settings' surfaces the Settings command as the top match"
        )

        // Return, via the software keyboard — a lone trailing newline on the
        // vertical-axis field, which `InputBar` turns into the highlighted result's
        // Enter rather than a literal newline.
        input.typeText("\n")

        // The Settings page pushes in over the launcher: its navigation-bar back
        // button appearing proves Return ran the highlighted result.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(
            back.waitForExistence(timeout: 10),
            "Return on the search input should run the highlighted result (push Settings), not insert a newline"
        )
    }
}
