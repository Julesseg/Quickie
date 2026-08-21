import XCTest

/// Every way the keyboard leaves, and where the input bar ends up (issues #64,
/// #58, #261). The lift is driven by hand rather than by SwiftUI's keyboard
/// avoidance, so each departure has to be told apart and answered:
///
/// - **Swipe down on a scrolling list** (#64): the native interactive dismissal
///   (`.scrollDismissesKeyboard(.interactively)`) — the bar drops and nothing
///   clears.
/// - **iPad's dedicated dismiss key** (#261): the bar drops too. It used to
///   freeze a keyboard's height above the bottom, because the notification is
///   indistinguishable from the one a context menu sends.
/// - **A long-press context menu** (#58): the bar must **not** move, or the
///   reversed list reflows out from under the open menu.
///
/// The last two are the same notification, told apart only because the app
/// reports the menu (`ContextMenuPresence`) — so they belong in one class, where
/// breaking either shows up immediately.
///
/// Only verifiable by driving the real app on a simulator, so it runs on the
/// XCUITest CI jobs.
final class KeyboardDismissUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Clean signals slate so persisted Favorites/Frecency can't change which
        // rows appear (mirrors the other UI suites). `extraArguments` lets a test
        // add hooks such as `-uitest-seed-frecent <id>`.
        app.launchArguments += ["-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// Swiping down on the Result list interactively dismisses the keyboard, and
    /// nothing clears: the query text and the surfaced results are preserved, so
    /// dismissing just gets the keyboard out of the way. Tapping the input field
    /// re-summons the keyboard — the only re-summon path.
    @MainActor
    func testSwipeDownOnResultListDismissesKeyboardAndPreservesQuery() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        // A broad query surfaces many rows, so the list is tall enough to scroll and
        // the drag registers as a real scroll-dismiss. "s" name-matches most command
        // rows plus the enabled fallbacks, which — since issue #197 — each surface a
        // second time (a ranked duplicate on top of the bottom fallback row), making
        // the list taller still.
        input.typeText("s")

        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 5),
            "typing surfaces the Settings command row"
        )
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "typing brings the keyboard up"
        )

        // Drag from the **Highlighted result row** (rank 0): it is always rendered
        // just above the input bar, so it stays on-screen however tall the list grows.
        // A specific mid-list command row (the old `builtin.settings` start) scrolls
        // off the top of a small screen once the list is long enough — the dual-row
        // fallbacks (issue #197) pushed it above the top edge on the CI iPhone SE — and
        // a drag begun from an off-screen coordinate never engages the list's pan.
        // Scope the "selected" lookup to result rows by id prefix so it can't match the
        // keyboard's selected shift key. `boosted`/`ranked`/`fallback` rows all carry a
        // `builtin.`/`seed.`-prefixed id here.
        let resultRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'builtin.' OR identifier BEGINSWITH 'seed.'")
        )
        XCTAssertTrue(resultRows.firstMatch.waitForExistence(timeout: 5), "the result list rendered")
        let row = resultRows.allElementsBoundByIndex.first { $0.isSelected }
        let highlighted = try XCTUnwrap(row, "the Highlighted result row (rank 0) is present and on-screen")

        // Drag down into the keyboard region, starting *on a result row* so the
        // gesture is owned by the result list's scroll view — that is the view
        // carrying `.scrollDismissesKeyboard(.interactively)`. (Targeting
        // `scrollViews.firstMatch` matched an unrelated tiny scroll view at the
        // keyboard's edge, so the list's pan never engaged.) Interactive dismiss
        // follows the finger over the keyboard and carries it off-screen; a quick
        // flick that never reaches the keyboard won't commit, so this is a firm,
        // continuous press-drag to the bottom of the screen (past the input bar,
        // over the keyboard), held briefly so the dismissal sticks.
        let start = highlighted.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .default,
            thenHoldForDuration: 0.4
        )

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "swiping down on the result list dismisses the keyboard"
        )

        // Bar drops, nothing clears: the query text and the results are unchanged.
        XCTAssertEqual(
            input.value as? String, "s",
            "dismissing the keyboard leaves the query text unchanged"
        )
        XCTAssertTrue(
            app.buttons["builtin.settings"].exists,
            "the results are preserved after dismissing the keyboard"
        )

        // Tapping the input field re-summons the keyboard — anywhere on it, not
        // only over the glyphs. Tap the *trailing empty space* (the clear button
        // sits outside the field's own frame, so this is still the field): a
        // `TextField(axis: .vertical)` only hit-tests around its text, which the
        // iPad leg caught the first time it ran — a tap beside a one-character
        // query landed on nothing and the keyboard never came back. The bar's
        // backing shape is what makes this point the field too; tapping here is
        // what keeps that from being quietly removed.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "tapping the input field re-summons the keyboard"
        )
    }

    /// The same swipe-down dismissal on Home's **Recent** (Frecency) list — the
    /// other scrolling list that adopted `.scrollDismissesKeyboard(.interactively)`
    /// (issue #71 closes the coverage gap left by #64). The Recent list only
    /// renders with frecency history, so the test seeds two entries through the
    /// real `SignalsStore.record` path via the `-uitest-seed-frecent` launch
    /// argument — no tapping rows to build history first. Two entries make the
    /// list a little taller and let the preserved-rows assertion cover more than
    /// a single row.
    @MainActor
    func testSwipeDownOnRecentListDismissesKeyboardAndPreservesRows() throws {
        let app = launchApp(extraArguments: [
            "-uitest-seed-frecent", "builtin.settings",
            "-uitest-seed-frecent", "builtin.pile-page",
        ])

        // Launch opens straight to Home (empty query, ADR 0012) with the seeded
        // Recent rows — identified by their Action ids, as in the Result list.
        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "seeding frecency renders the Recent list")
        let otherRow = app.buttons["builtin.pile-page"]
        XCTAssertTrue(otherRow.exists, "every seeded entry appears as a Recent row")

        // Bring the keyboard up over Home. Tapping the field (rather than relying
        // on launch auto-focus alone) makes the precondition explicit.
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "tapping the input brings the keyboard up over Home"
        )

        // Same firm, continuous press-drag as the Result-list test: start on a
        // Recent row so the gesture is owned by the Recent list's scroll view —
        // the view carrying `.scrollDismissesKeyboard(.interactively)` — and
        // carry the keyboard off-screen, holding briefly so the dismissal sticks.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .default,
            thenHoldForDuration: 0.4
        )

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "swiping down on the Recent list dismisses the keyboard"
        )

        // The bar drops and nothing clears: the Recent rows stay put.
        XCTAssertTrue(row.exists, "the Recent rows are preserved after dismissing the keyboard")
        XCTAssertTrue(otherRow.exists, "every seeded Recent row survives the dismissal")
    }

    /// iPad's software keyboard carries a dedicated dismiss key. Pressing it puts
    /// the keyboard away for good — unlike a context menu, nothing is coming back
    /// — so the bar must drop to the window bottom instead of hanging a
    /// keyboard's height above it (issue #261).
    ///
    /// Skipped where there is no software keyboard with a dismiss key to press:
    /// iPhone's keyboard has none, and a simulator with a hardware keyboard
    /// attached shows only the shortcuts bar, whose dismissal reports a
    /// zero-height frame that never held the inset in the first place. Asserting
    /// against that would pass for free.
    @MainActor
    func testDismissKeyDropsTheBarToTheBottom() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "bottom input should exist on launch")
        input.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "tapping the input brings the keyboard up"
        )
        // Let it finish rising: mid-animation its keys report a hit point of
        // {-1, -1} and the tap silently no-ops.
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let keyboard = app.keyboards.firstMatch
        try XCTSkipIf(
            keyboard.keys.count < 10,
            "no full software keyboard here — a hardware keyboard leaves only the shortcuts bar"
        )
        let dismissKey = keyboard.buttons["Hide keyboard"]
        try XCTSkipUnless(dismissKey.exists, "only the iPad keyboard carries a dismiss key")

        let lifted = input.frame.maxY
        dismissKey.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "the dismiss key puts the keyboard away"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let dropped = input.frame.maxY
        XCTAssertGreaterThan(
            dropped, lifted,
            "the bar must move down when the keyboard goes — it sat at \(lifted)pt before and after"
        )
        // It rests in the bottom safe area, not a keyboard's height above it.
        let bottomGap = app.frame.maxY - dropped
        XCTAssertLessThan(
            bottomGap, 120,
            "the bar sat \(bottomGap)pt above the bottom after the dismiss key — the held inset was not released (issue #261)"
        )
    }

    /// The counterweight, and the behaviour issue #58 exists for: a long-press
    /// menu drops the keyboard too, and there the bar must **not** move. The two
    /// notifications are identical, so this passing while the test above also
    /// passes is the only proof the menu signal is read at all.
    @MainActor
    func testLongPressMenuLeavesTheBarWhereItIs() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        let thought = "Buy milk and eggs"
        input.typeText(thought)

        // Stage it through the always-present "Save for later" Fallback, then
        // search it back up: a Pile entry is the content-bearing row whose menu
        // the suite already drives (SecondaryActionUITests).
        let saveForLater = app.buttons["builtin.save-for-later"]
        XCTAssertTrue(saveForLater.waitForExistence(timeout: 10))
        saveForLater.tap()

        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(thought)
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "typing keeps the keyboard up"
        )
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", thought)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let lifted = input.frame.maxY
        row.press(forDuration: 1.3)

        // Prove the menu opened before asserting anything about it — a long-press
        // that missed would make this test pass for free.
        XCTAssertTrue(
            app.buttons["Copy"].waitForExistence(timeout: 10),
            "the long-press opens the row's menu"
        )
        XCTAssertEqual(
            input.frame.maxY, lifted, accuracy: 2,
            "the long-press must not move the input bar — the list has to stay still under the menu (issue #58)"
        )
    }
}
