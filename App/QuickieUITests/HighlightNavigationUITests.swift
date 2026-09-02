import XCTest

/// Arrow-key navigation of the **Highlighted result** (CONTEXT.md → Highlighted
/// result; issue #267), driven through the real app.
///
/// This is the one part of the launcher's keyboard loop XCUITest *can* reach.
/// `KeyCommandUITests` records the measurement behind that: a synthesized ⌘ chord
/// or `esc` never fires any binding on a simulator, through four independent
/// mechanisms — the press arrives on the text-input path and not the key-command
/// path. Unmodified ↑/↓ are text-editing keys, so they travel the path that does
/// arrive, and the highlight they move is observable: the highlighted row carries
/// the `.isSelected` accessibility trait (`ActionRow`), which is also what a
/// VoiceOver user hears.
final class HighlightNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting", "-uitest-reset-signals", "-uitest-instant-motion",
        ]
        app.launch()
        return app
    }

    /// The result rows, scoped by id prefix so the lookup can never match the
    /// software keyboard's own selected shift key — `boosted`, `ranked` and
    /// `fallback` rows all carry a `builtin.`/`seed.`-prefixed id here.
    @MainActor
    private func resultRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'builtin.' OR identifier BEGINSWITH 'seed.'")
        )
    }

    /// The id of the row wearing the highlight, polled until exactly one row does.
    /// Polled rather than read once because an arrow key re-renders the list, and a
    /// snapshot taken mid-update legitimately catches no highlight at all.
    @MainActor
    private func highlightedRow(
        in app: XCUIApplication,
        until matches: (String) -> Bool = { _ in true },
        timeout: TimeInterval = 10
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let selected = resultRows(in: app).allElementsBoundByIndex.filter(\.isSelected)
            if selected.count == 1, matches(selected[0].identifier) {
                return selected[0].identifier
            }
            // Paced, not spun: a miss usually means the list is mid-update, and a
            // hot loop of accessibility snapshots would compete with the very
            // render it is waiting for on a loaded CI runner.
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    /// Types a query that surfaces several rows and returns the app with the
    /// highlight where every touch-driven session leaves it: on the best match.
    @MainActor
    private func launchWithResults() throws -> (app: XCUIApplication, best: String) {
        let app = launchApp()
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        app.typeText("se")
        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "\"se\" should surface a result list to walk"
        )
        let best = try XCTUnwrap(highlightedRow(in: app), "the best match wears the highlight")
        return (app, best)
    }

    /// ↑ walks the highlight off the best match and ↓ walks it back — the loop the
    /// whole ticket is for.
    @MainActor
    func testArrowKeysWalkTheHighlightAndBack() throws {
        let (app, best) = try launchWithResults()

        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        let walked = highlightedRow(in: app, until: { $0 != best })
        XCTAssertNotNil(walked, "↑ should walk the highlight off the best match")

        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        XCTAssertNotNil(
            highlightedRow(in: app, until: { $0 == best }),
            "↓ should walk the highlight back onto the best match"
        )
    }

    /// ↓ on the best match has nowhere to go: the highlight stays put rather than
    /// wrapping round to the weakest row.
    @MainActor
    func testDownOnTheBestMatchDoesNotWrap() throws {
        let (app, best) = try launchWithResults()

        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])

        XCTAssertEqual(
            highlightedRow(in: app),
            best,
            "the highlight should stay on the best match rather than wrap to the weakest"
        )
    }

    /// Return runs the row the highlight landed on, not the best match it left.
    @MainActor
    func testReturnRunsTheWalkedRow() throws {
        let (app, best) = try launchWithResults()

        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        let walked = highlightedRow(in: app, until: { $0 != best })
        XCTAssertEqual(
            walked,
            "builtin.settings",
            "\"se\" ranks the Settings command row directly above the best match"
        )

        app.typeText("\n")

        XCTAssertTrue(
            app.descendants(matching: .any)["appearance-picker"].firstMatch.waitForExistence(timeout: 10),
            "Return should open the Settings hub — the row the highlight walked onto"
        )
    }

    /// A keystroke re-ranks the results, so it re-arms the best match however far
    /// the highlight had walked — including a backspace back to a query the
    /// highlight was walked against before, which is a query the user has now typed
    /// twice and where the best match is primed both times.
    @MainActor
    func testTypingRePrimesTheBestMatch() throws {
        let (app, best) = try launchWithResults()
        let input = app.textFields["search-input"]

        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        XCTAssertNotNil(highlightedRow(in: app, until: { $0 != best }), "↑ walks the highlight")

        // "set", then back to "se": same query, same rows, and the highlight is on
        // the best match rather than back where ↑ had left it.
        input.typeText("t")
        input.typeText(XCUIKeyboardKey.delete.rawValue)

        XCTAssertEqual(
            highlightedRow(in: app, until: { $0 == best }),
            best,
            "typing should re-prime the best match"
        )
    }
}
