import XCTest

/// Throwaway iPad UI-audit driver — NOT a behavioral test. Walks the app's
/// surfaces on an iPad simulator and saves full-screen PNGs to the host
/// directory named by the `SCREENSHOT_DIR` env var (pass it as
/// `TEST_RUNNER_SCREENSHOT_DIR` on the xcodebuild invocation). Every step is
/// guarded so a missing element skips that shot instead of aborting the walk.
final class IPadExplorerUITests: XCTestCase {

    private var shotDir: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: shotDir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
    }

    /// Clears any current query and types a fresh one.
    private func search(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields["search-input"]
        guard input.waitForExistence(timeout: 10) else { return }
        let clear = app.buttons["clear-input"]
        if clear.exists { clear.tap() }
        input.tap()
        input.typeText(text)
    }

    /// Types a query, taps the command row, waits for `anchor`, snaps, and
    /// runs `also` while on the page.
    private func visit(
        _ app: XCUIApplication,
        query: String,
        row: String,
        anchor: XCUIElement,
        shot: String,
        also: (() -> Void)? = nil
    ) {
        search(app, query)
        let target = app.buttons[row].firstMatch
        guard target.waitForExistence(timeout: 5) else { return }
        target.tap()
        _ = anchor.waitForExistence(timeout: 10)
        sleep(1)
        snap(shot)
        also?()
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) { back.tap() }
        sleep(1)
    }

    @MainActor
    func testExploreAllScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-uitest-reset-signals",
            "-uitest-instant-motion",
            "-uitest-reset-folders",
            "-uitest-seed-files",
            "-uitest-stub-reminders",
            "-uitest-pin-favorite", "builtin.settings",
        ]
        app.launch()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        sleep(2)

        // ── Portrait ──────────────────────────────────────────────────────
        snap("10-home-populated")

        // Result list: a calculation and a ranked multi-row list.
        search(app, "2+2")
        sleep(1)
        snap("11-results-calc")

        search(app, "se")
        sleep(1)
        snap("12-results-ranked")

        // Settings hub and every provider page reachable from it.
        let hubAnchor = app.descendants(matching: .any)["settings-show-recents"].firstMatch
        visit(app, query: "settings", row: "builtin.settings", anchor: hubAnchor, shot: "20-settings-hub") {
            let pages: [(String, String)] = [
                ("custom-actions", "21-settings-custom-actions"),
                ("fallbacks", "22-settings-fallbacks"),
                ("snippets", "23-settings-snippets"),
                ("shortcuts", "24-settings-shortcuts"),
                ("system", "25-settings-system"),
                ("calculator", "26-settings-computed"),
                ("file-search", "27-settings-file-search"),
            ]
            for (raw, shot) in pages {
                let row = app.descendants(matching: .any)["settings-provider-\(raw)"].firstMatch
                guard row.waitForExistence(timeout: 5) else { continue }
                row.tap()
                let anchor = app.descendants(matching: .any)["provider-enabled-\(raw)"].firstMatch
                _ = anchor.waitForExistence(timeout: 10)
                sleep(1)
                self.snap(shot)

                if raw == "custom-actions" {
                    let add = app.buttons["add-custom-action"].firstMatch
                    if add.waitForExistence(timeout: 5) {
                        add.tap()
                        let name = app.textFields["custom-action-name-field"].firstMatch
                        _ = name.waitForExistence(timeout: 10)
                        sleep(1)
                        self.snap("21b-custom-action-editor-sheet")
                        let cancel = app.buttons["Cancel"].firstMatch
                        if cancel.exists { cancel.tap() }
                        sleep(1)
                    }
                    let catalog = app.buttons["browse-catalog"].firstMatch
                    if catalog.waitForExistence(timeout: 5) {
                        catalog.tap()
                        sleep(2)
                        self.snap("21c-catalog")
                        self.goBack(app)
                    }
                }
                if raw == "snippets" {
                    let add = app.buttons["snippet-add"].firstMatch
                    if add.waitForExistence(timeout: 5) {
                        add.tap()
                        let title = app.textFields["snippet-title-field"].firstMatch
                        _ = title.waitForExistence(timeout: 10)
                        sleep(1)
                        self.snap("23b-snippet-editor-sheet")
                        let cancel = app.buttons["Cancel"].firstMatch
                        if cancel.exists { cancel.tap() }
                        sleep(1)
                    }
                }
                self.goBack(app)
            }
            // Leave the hub back to the launcher.
            self.goBack(app)
        }

        // Search Files context (seeded folder).
        search(app, "files")
        let filesRow = app.buttons["builtin.search-files"].firstMatch
        if filesRow.waitForExistence(timeout: 5) {
            filesRow.tap()
            let crumb = app.descendants(matching: .any)["file-search-breadcrumb"].firstMatch
            _ = crumb.waitForExistence(timeout: 10)
            sleep(1)
            snap("30-file-search-context")
            let cancel = app.buttons["file-search-cancel"].firstMatch
            if cancel.exists { cancel.tap() }
            sleep(1)
        }

        // Reminder capture flow (stubbed EventKit).
        search(app, "new reminder")
        let remRow = app.buttons["builtin.new-reminder"].firstMatch
        if remRow.waitForExistence(timeout: 5) {
            remRow.tap()
            let capture = app.descendants(matching: .any)["capture-input"].firstMatch
            _ = capture.waitForExistence(timeout: 10)
            sleep(1)
            snap("40-capture-reminder")
            if capture.exists {
                capture.tap()
                capture.typeText("Buy milk\n")
                sleep(1)
                snap("41-capture-reminder-list-step")
            }
            let setDate = app.buttons["capture-set-date"].firstMatch
            if setDate.waitForExistence(timeout: 3) {
                setDate.tap()
                sleep(1)
                snap("42-capture-reminder-date-step")
            }
            let cancel = app.buttons["capture-cancel"].firstMatch
            if cancel.exists { cancel.tap() }
            sleep(1)
        }

        // Pile.
        let pileAnchor = app.descendants(matching: .any)["pile-header"].firstMatch
        visit(app, query: "pile", row: "builtin.pile-page", anchor: pileAnchor, shot: "50-pile") {
            self.goBack(app)
        }

        // ── Landscape ─────────────────────────────────────────────────────
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)

        search(app, "")
        let clear = app.buttons["clear-input"].firstMatch
        if clear.exists { clear.tap() }
        sleep(1)
        snap("60-home-landscape")

        search(app, "2+2")
        sleep(1)
        snap("61-results-landscape")

        visit(app, query: "settings", row: "builtin.settings", anchor: hubAnchor, shot: "62-settings-landscape") {
            self.goBack(app)
        }

        search(app, "new reminder")
        let remRow2 = app.buttons["builtin.new-reminder"].firstMatch
        if remRow2.waitForExistence(timeout: 5) {
            remRow2.tap()
            sleep(2)
            snap("63-capture-landscape")
            let cancel = app.buttons["capture-cancel"].firstMatch
            if cancel.exists { cancel.tap() }
        }

        XCUIDevice.shared.orientation = .portrait
    }
}
