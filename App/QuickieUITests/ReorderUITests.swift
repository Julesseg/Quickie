import XCTest

/// Drag-to-reorder **commit** coverage — the layer no other test drives. Core's
/// `FallbackTiersTests` and `CustomActionEditorTests` pin the reorder *logic*, but
/// the List-layer commit (the grip drag actually landing when released) broke
/// silently on both the Fallbacks page and the Custom Action editor with the whole
/// suite green, so the gesture gets driven for real here despite the old caution
/// that a raw drag is environment-sensitive: a regression nothing can see is worse
/// than a test that needs a retry.
///
/// Each surface asserts two independent facts, separable on failure via the
/// UI-test-only **order probe** (the section header's accessibility value, exposing
/// the stored order under `--uitesting`):
/// - the probe changed → `onMove` fired and the model committed;
/// - the row frames swapped → the List rendered the committed order.
/// A drag that leaves the probe untouched means `onMove` never fired; a changed
/// probe with unswapped frames means the model moved but the rows sprang back.
final class ReorderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Clean fallback/signal slate and instant motion, like every suite. The
        // clean slate seeds Active with the first-run defaults, so the Fallbacks
        // test can lean on two known adjacent rows without promoting its own.
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    // MARK: - Shared helpers

    /// The row (cell) whose label contains `title`, nudged into the render tree
    /// (same both-directions walk as `FallbackShelfUITests`).
    @MainActor
    private func cell(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        for _ in 0..<4 where !cell.exists { app.swipeDown() }
        for _ in 0..<5 where !cell.exists { app.swipeUp() }
        return cell
    }

    /// Drags `row` by its reorder grip to `target`'s position. The system grip
    /// sits at the trailing edge of the cell in edit mode; a slow press-drag-hold
    /// is the reliable way to engage the reorder session rather than a scroll.
    /// `targetOffset` is where in the target cell to release: below its middle to
    /// land after it, above to land before it.
    @MainActor
    private func dragRow(_ row: XCUIElement, to target: XCUIElement, targetOffset: CGVector) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: targetOffset)
        start.press(forDuration: 1.0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// Polls until `condition` holds or the timeout passes; returns the last read.
    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        return condition()
    }

    // MARK: - Fallbacks page

    /// Dragging the top Active fallback below the second one commits: the stored
    /// order changes (probe) and the rows render swapped (frames).
    @MainActor
    func testActiveFallbackDragReorderCommits() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("fallbacks")
        let command = app.buttons["builtin.fallbacks-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing 'fallbacks' surfaces its command row")
        command.tap()

        // The clean-slate seed puts "Search the web" first and "Search the App
        // Store" second in Active; the Shelf starts empty so they sit near the top.
        let web = cell(app, titled: "Search the web")
        XCTAssertTrue(web.waitForExistence(timeout: 10), "the seeded web-search fallback is Active")
        let store = cell(app, titled: "Search the App Store")
        XCTAssertTrue(store.waitForExistence(timeout: 10), "the seeded App Store fallback is Active")
        XCTAssertLessThan(web.frame.minY, store.frame.minY, "seed order: web search above App Store")

        let header = app.staticTexts["Active"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "the Active section header exists")
        let probeBefore = header.value as? String ?? ""
        XCTAssertFalse(probeBefore.isEmpty, "the UI-test order probe is populated under --uitesting")

        dragRow(web, to: store, targetOffset: CGVector(dx: 0.94, dy: 0.85))

        // The store must have moved (onMove fired and committed)…
        let probeMoved = waitUntil(timeout: 5) { (header.value as? String ?? "") != probeBefore }
        let probeAfter = header.value as? String ?? ""
        XCTAssertTrue(
            probeMoved,
            "onMove never fired: the stored Active order is still \(probeAfter)"
        )
        // …and the rows must render the committed order, not spring back.
        let framesSwapped = waitUntil(timeout: 5) {
            let webAfter = app.cells.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "Search the web")).firstMatch
            let storeAfter = app.cells.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "Search the App Store")).firstMatch
            return webAfter.exists && storeAfter.exists
                && webAfter.frame.minY > storeAfter.frame.minY
        }
        XCTAssertTrue(
            framesSwapped,
            "the store moved (\(probeBefore) → \(probeAfter)) but the rows sprang back"
        )
    }

    // MARK: - Custom Action editor arguments

    /// Dragging the second argument row above the first sets the fill order: the
    /// stored order changes (probe) and the rows render swapped (frames).
    @MainActor
    func testArgumentRowDragReorderCommits() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("custom actions")
        let command = app.buttons["builtin.custom-actions-page"]
        XCTAssertTrue(command.waitForExistence(timeout: 5), "typing surfaces the Custom Actions page row")
        command.tap()

        let add = app.buttons["add-custom-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the page offers an Add button")
        add.tap()

        let urlField = app.textFields["custom-action-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), "the editor opens on the URL field")
        urlField.tap()
        urlField.typeText("app://x?t={title}&n={notes}")
        XCTAssertTrue(app.textFields["custom-action-arg.title"].waitForExistence(timeout: 5),
                      "the {title} slot mirrors into a row")
        XCTAssertTrue(app.textFields["custom-action-arg.notes"].waitForExistence(timeout: 5),
                      "the {notes} slot mirrors into a row")

        // Enter edit mode so the grips show.
        let edit = app.buttons["custom-action-reorder"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the Arguments header offers Edit")
        edit.tap()

        let titleRow = app.cells.containing(.textField, identifier: "custom-action-arg.title").firstMatch
        let notesRow = app.cells.containing(.textField, identifier: "custom-action-arg.notes").firstMatch
        XCTAssertTrue(titleRow.waitForExistence(timeout: 5))
        XCTAssertTrue(notesRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(titleRow.frame.minY, notesRow.frame.minY, "URL order: title above notes")

        let header = app.staticTexts["Arguments"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "the Arguments section header exists")
        let probeBefore = header.value as? String ?? ""
        XCTAssertEqual(probeBefore, "title,notes", "the probe reads the fill order")

        // Drag notes above title: release near the top of the title row.
        dragRow(notesRow, to: titleRow, targetOffset: CGVector(dx: 0.94, dy: 0.15))

        let probeMoved = waitUntil(timeout: 5) { (header.value as? String ?? "") == "notes,title" }
        let probeAfter = header.value as? String ?? ""
        XCTAssertTrue(
            probeMoved,
            "onMove never fired (or moved wrong): the stored fill order is \(probeAfter)"
        )
        let framesSwapped = waitUntil(timeout: 5) {
            let titleAfter = app.cells.containing(.textField, identifier: "custom-action-arg.title").firstMatch
            let notesAfter = app.cells.containing(.textField, identifier: "custom-action-arg.notes").firstMatch
            return titleAfter.exists && notesAfter.exists
                && notesAfter.frame.minY < titleAfter.frame.minY
        }
        XCTAssertTrue(
            framesSwapped,
            "the fill order moved (\(probeBefore) → \(probeAfter)) but the rows sprang back"
        )
    }
}
