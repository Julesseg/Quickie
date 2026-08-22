import XCTest

/// How the launcher's **modal surfaces** present on a regular-width window (issue
/// #264, iPad audit findings F9 and F11):
///
/// - **Share** — a transient action on one specific row — is a popover with its arrow
///   in that row, not a sheet rising from the bottom of the window with nothing left on
///   screen to say which result is about to be shared. Compact width keeps the sheet.
/// - The **Snippet** and **Custom Action** editors are form sheets: a centered card,
///   not a slab the width of an iPad. On an iPhone they stay the full-height sheet they
///   have always been.
///
/// Which shape Share takes is pinned in QuickieCore (`SharePresentationTests`). What
/// only a simulator can prove is the part the policy can't state: that the popover
/// actually lands **on the row** — that its arrow's anchor is the pressed row's own
/// frame and not the launcher's.
///
/// Both legs of the CI matrix run this (ADR 0038). Like `CommandColumnUITests`, the
/// expectation is picked by **device idiom** only because the suite runs full-screen
/// and portrait, where a full-screen iPad is regular width and every iPhone is
/// compact; the app itself keys off the size class, never the idiom.
///
/// The share is **always closed again**, including on the way out of a failure: the
/// iOS share sheet is a remote view service that outlives the app process, so one left
/// standing hides the launcher from the *next* test in the shard — which is also why
/// only one test here opens one at all.
final class ModalPresentationUITests: XCTestCase {

    /// The popover's content width, mirroring `SharePresentation.popoverSize`.
    /// Duplicated here rather than imported because a UI test target can't see
    /// QuickieCore; Core's own test pins the value, so a change to it fails there
    /// first, loudly.
    private let popoverWidth: CGFloat = 375

    private var isRegularWidth: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        // Best effort, and deliberately unasserted: whatever the test proved or failed
        // to prove, the next one must open on the launcher and not on a share sheet.
        MainActor.assumeIsolated { _ = Self.dismissShare(in: XCUIApplication()) }
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// The presented share sheet's own view, whichever way it is presented — the one
    /// element the popover and the sheet have in common.
    @MainActor
    private func activityList(in app: XCUIApplication) -> XCUIElement {
        app.otherElements["ActivityListView"]
    }

    /// Types a whole-query URL and returns its **Detected result** row — the quickest
    /// content-bearing row in the app, and one whose Share verb needs no stored record
    /// to exist first (ADR 0032).
    @MainActor
    private func detectedURLRow(in app: XCUIApplication) -> XCUIElement {
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        input.typeText("apple.com")

        let row = app.buttons["detect.url"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "a bare domain surfaces the Open row")
        return row
    }

    /// Long-presses `row`, runs its **Share** verb, and waits for the share to appear.
    @MainActor
    private func share(from row: XCUIElement, in app: XCUIApplication) {
        let share = app.buttons["Share"]
        // A long press that lands while the row is still settling opens no menu at all,
        // and there is no signal to wait on beforehand — so press again. Three presses
        // and no menu is a real failure, not a slow simulator.
        var opened = false
        for _ in 0..<3 where !opened {
            row.press(forDuration: 1.3)
            opened = share.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(opened, "a detected URL row's menu offers Share")
        share.tap()

        // Generous: the iOS share sheet is a remote view service, and the *first*
        // presentation after a cold simulator boot waits on it launching.
        XCTAssertTrue(
            activityList(in: app).waitForExistence(timeout: 30),
            "running Share presents the iOS share sheet"
        )
    }

    /// Closes whichever share surface is up, and reports whether none is left.
    ///
    /// A popover answers to a tap outside itself; the compact sheet has no outside, so
    /// it answers to its own Close button — and *not* to a swipe on the activity list,
    /// which scrolls the app row instead of dragging the sheet. Either way the tap can
    /// land on a surface still presenting and be swallowed, so it is worth repeating;
    /// three rounds with nothing gone is a real failure.
    @MainActor
    @discardableResult
    private static func dismissShare(in app: XCUIApplication) -> Bool {
        let list = app.otherElements["ActivityListView"]
        let close = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "header.closeButton", "Close")
        ).firstMatch

        for _ in 0..<3 {
            guard list.exists else { return true }
            if app.popovers.firstMatch.exists {
                tapClearOfThePopover(in: app)
            } else if close.waitForExistence(timeout: 3) {
                close.tap()
            }
            if list.waitForNonExistence(timeout: 10) { return true }
        }
        return !list.exists
    }

    /// Taps the one part of the window that is neither the popover nor a row behind it.
    ///
    /// Tapping the system's own `PopoverDismissRegion` element looks like the obvious
    /// way out and is a trap: XCUITest aims a tap at an element's centre, and that
    /// region *is* the whole window — whose centre lands inside the popover it is meant
    /// to dismiss, or, when XCUITest re-aims for a hittable point, on a [[Result list]]
    /// row behind it. A tap there **runs that row**, which clears the query and looks
    /// exactly like the launcher losing the user's typing.
    ///
    /// 40pt down the window is clear of both: the rows begin far below it, and a
    /// popover reaching that high would have no row left underneath to anchor to.
    @MainActor
    private static func tapClearOfThePopover(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: 40))
            .tap()
    }

    // MARK: - F9: the Share popover

    /// Share opens on the row that spawned it and closes back to the input: at regular
    /// width a popover whose arrow points into that row, at compact the sheet that ships
    /// today — and either way, dismissing re-arms the input's focus.
    ///
    /// One test rather than one per claim because each presentation drives the *system*
    /// share sheet, whose remote view outlives the app process: opening it twice is
    /// twice the chance of leaving one standing over the next test in the shard.
    ///
    /// It drives a [[Result list]] row, and only that one, for the same reason. Every
    /// surface whose rows carry the long-press menu — Home's Favorites grid and Recent
    /// list, the [[Shelf]] — presents through the *one* `resultContextMenu` seam and
    /// the one anchor it hands down, so the mechanism under test is shared rather than
    /// re-implemented per surface. A Detected result is simply the only content-bearing
    /// row (the only kind that offers Share at all) reachable in one keystroke: Home's
    /// rows need an Action run first to become Recent, and the Shelf's four defaults
    /// carry no content to share.
    @MainActor
    func testShareOpensOnItsRowAndClosesBackToTheInput() throws {
        let app = launchApp()
        let window = app.frame
        let row = detectedURLRow(in: app)
        let rowFrame = row.frame
        share(from: row, in: app)

        if isRegularWidth {
            let popover = app.popovers.firstMatch
            XCTAssertTrue(popover.waitForExistence(timeout: 15), "at regular width Share is a popover")

            XCTAssertEqual(
                popover.frame.width, popoverWidth, accuracy: 1,
                "the popover carries the explicit content width the policy states"
            )
            XCTAssertLessThan(
                popover.frame.width, window.width - 32,
                "a popover the width of the window would be a sheet with an arrow"
            )
            // Anchored *to the row*: the arrow's origin sits inside the row's own
            // horizontal extent, which is what "points at that row" means for a popover
            // the system is free to place above or below it.
            XCTAssertGreaterThan(popover.frame.midX, rowFrame.minX,
                                 "the popover should point into the row, not off its leading edge")
            XCTAssertLessThan(popover.frame.midX, rowFrame.maxX,
                              "the popover should point into the row, not off its trailing edge")
            // …and it sits against one of the row's two long edges rather than floating
            // somewhere else on screen. 24pt covers the arrow plus the system's own gap.
            let gapAbove = rowFrame.minY - popover.frame.maxY
            let gapBelow = popover.frame.minY - rowFrame.maxY
            XCTAssertTrue(
                (gapAbove >= 0 && gapAbove < 24) || (gapBelow >= 0 && gapBelow < 24),
                "the popover should sit against the row it points at (above by \(gapAbove)pt, below by \(gapBelow)pt)"
            )
        } else {
            // Compact: unchanged. The popover adapts to a sheet — there is nothing
            // anchored to anything, which is the whole of the compact claim.
            XCTAssertEqual(app.popovers.count, 0, "at compact width Share must stay a sheet")
        }

        // Dismissing re-arms the input's focus — the sheet path has always done it in
        // `onDismiss`, which a popover has no callback for and which the launcher
        // therefore drives off the presenter instead.
        XCTAssertTrue(Self.dismissShare(in: app), "the share should dismiss")

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the launcher's input is back")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "dismissing the share re-arms the input's focus, so the keyboard comes back up"
        )
        XCTAssertEqual(input.value as? String, "apple.com",
                       "a secondary action never touches the query")
    }

    // MARK: - F11: the editors' sheet sizing

    /// An editor's sheet is a **form sheet**: a centered card on an iPad, the
    /// full-width sheet on an iPhone. `formSheetSizing()` states it; this measures it.
    ///
    /// The editor's navigation bar spans its sheet, so its frame *is* the sheet's.
    @MainActor
    private func assertFormSheet(titled title: String, in app: XCUIApplication) {
        let window = app.frame
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the editor carries its own title bar")

        if isRegularWidth {
            XCTAssertLessThan(
                bar.frame.width, window.width - 32,
                "on iPad the editor is a form-sheet card, not a slab the width of the window"
            )
            XCTAssertEqual(
                bar.frame.midX, window.midX, accuracy: 1,
                "a form sheet is centered in the window"
            )
        } else {
            XCTAssertEqual(
                bar.frame.width, window.width, accuracy: 1,
                "on iPhone the editor stays the full-width sheet it has always been"
            )
        }
    }

    /// The Snippet editor, reached the way a user meets it most: seeded from the typed
    /// query by the always-present New Snippet Fallback.
    @MainActor
    func testTheSnippetEditorPresentsAsAFormSheet() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        input.typeText("Hello from Quickie")

        let newSnippet = app.buttons["builtin.new-snippet"]
        XCTAssertTrue(newSnippet.waitForExistence(timeout: 10), "the New Snippet Fallback is always offered")
        newSnippet.tap()

        XCTAssertTrue(
            app.textFields["snippet-title-field"].waitForExistence(timeout: 15),
            "the Snippet editor opens"
        )
        assertFormSheet(titled: "New Snippet", in: app)
    }

    /// The Custom Action editor — the second of the two editors finding F11 named —
    /// reached from its own Management page.
    @MainActor
    func testTheCustomActionEditorPresentsAsAFormSheet() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()
        input.typeText("custom actions")

        let page = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), "typing 'custom actions' surfaces the command row")
        page.tap()

        let add = app.buttons["add-custom-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the Custom Actions page offers an Add button")
        add.tap()

        XCTAssertTrue(
            app.textFields["custom-action-name-field"].waitForExistence(timeout: 15),
            "the Custom Action editor opens"
        )
        assertFormSheet(titled: "New Custom Action", in: app)
    }
}
