import XCTest
import UIKit

/// The **readable command column** as the user meets it (CONTEXT.md → Readable
/// command column; ADR 0039; issue #260): on a regular-width window the launcher's
/// command surfaces lay out in one centred, readable column instead of stretching to
/// the window's edges; on a compact one nothing moves.
///
/// The width and the regular-vs-compact switch are pinned in QuickieCore
/// (`CommandColumnTests`). What only a simulator can prove is that the surfaces
/// actually *share* the column — that the input bar and a result row come out on the
/// same centre line, inside the same width — which is the whole point: one edge
/// running down the screen through every surface, not a per-view number that drifted.
///
/// Both legs of the CI matrix run this (ADR 0038). The expectation is picked by
/// **device idiom** only because the suite runs full-screen and portrait, where a
/// full-screen iPad is regular width and every iPhone is compact; the app itself
/// keys off the size class, never the idiom, which is what lets the same window
/// resized narrow revert to the compact layout.
final class CommandColumnUITests: XCTestCase {

    /// The column's width, mirroring `CommandColumn.readableWidth`. Duplicated here
    /// rather than imported because a UI test target can't see QuickieCore; Core's
    /// own test pins the value, so a change to it fails there first, loudly.
    private let readableWidth: CGFloat = 680

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        // An empty clipboard, so the paste chip is not offered and the input bar is
        // the bar's only occupant — otherwise the field sits off-centre beside the
        // chip, and *which* is true depends on whichever suite ran before this one.
        UIPasteboard.general.items = []
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"]
        app.launch()
        return app
    }

    /// The input bar and a result row lay out on the same centre line, inside the
    /// same width — and at regular width that width is the column, well short of the
    /// window's own.
    @MainActor
    func testInputBarAndResultRowShareOneCentredColumn() throws {
        let app = launchApp()
        let window = app.frame

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")

        // Measured while the query is empty: the field's insets are symmetric until
        // the clear button arrives, so an empty field's centre *is* the bar's centre.
        let emptyField = input.frame
        XCTAssertEqual(
            emptyField.midX, window.midX, accuracy: 2,
            "the input bar should be centred in the window"
        )

        input.tap()
        input.typeText("settings")

        let row = app.buttons["builtin.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "typing 'settings' surfaces its command row")

        // A row spans its surface's whole column, so its frame *is* the column.
        XCTAssertEqual(
            row.frame.midX, window.midX, accuracy: 1,
            "the result rows should be centred in the window, on the input bar's centre line"
        )
        XCTAssertLessThanOrEqual(
            emptyField.width, row.frame.width + 1,
            "the input bar must not run wider than the column the results lay out in"
        )

        if UIDevice.current.userInterfaceIdiom == .pad {
            // Regular width: the column, not the window.
            XCTAssertEqual(
                row.frame.width, readableWidth, accuracy: 1,
                "at regular width a result row should lay out in the \(readableWidth)pt column"
            )
            XCTAssertLessThan(
                row.frame.width, window.width - 32,
                "the column should leave a real margin on a full-screen iPad"
            )
        } else {
            // Compact width: unchanged — the row still spans the window edge to edge,
            // its glass inset by its own padding exactly as it always was.
            XCTAssertEqual(
                row.frame.width, window.width, accuracy: 1,
                "at compact width the layout must be unchanged: rows span the window"
            )
        }
    }
}
