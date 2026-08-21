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

    /// The Favorites grid's inset off the column's edge and the gutter between its
    /// cards, mirroring `CommandColumn.FavoritesGrid.horizontalInset` / `.spacing`
    /// for the same reason as `readableWidth` above: the UI test target can't see
    /// QuickieCore, and Core's own test pins both values so a change fails there
    /// first. Named rather than inlined so the expectations below read as the
    /// policy's arithmetic instead of as bare numbers.
    private let gridInset: CGFloat = 16
    private let gridSpacing: CGFloat = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        // An empty clipboard, so the paste chip is not offered and the input bar is
        // the bar's only occupant — otherwise the field sits off-centre beside the
        // chip, and *which* is true depends on whichever suite ran before this one.
        UIPasteboard.general.items = []
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-uitest-reset-signals", "-uitest-instant-motion"] + extraArguments
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

    /// Home's Recent rows share the column with the Result list that replaces them
    /// on the first keystroke.
    ///
    /// Home is the launcher's default screen and the one surface where the mismatch
    /// is visible without typing anything: a centred input bar over edge-to-edge
    /// Recents. The two lists render the *same* `ActionRow`, so "they line up" is
    /// the honest assertion — a Recent row and a result row on the same two edges.
    @MainActor
    func testHomeRecentRowsShareTheResultListColumn() throws {
        let app = launchApp()

        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")

        // A launch with `-uitest-reset-signals` has no Recents, so earn one: run the
        // Settings row and pop back. Frecency then puts it on Home.
        input.tap()
        input.typeText("settings")
        let resultRow = app.buttons["builtin.settings"]
        XCTAssertTrue(resultRow.waitForExistence(timeout: 10), "typing 'settings' surfaces its command row")
        let resultRowWidth = resultRow.frame.width
        let resultRowMidX = resultRow.frame.midX
        resultRow.tap()

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the pushed Settings page shows a back button")
        back.tap()

        // Back on Home with an empty query (the push cleared it), Settings is now a
        // Recent — the same id, so this is the same Action rendered by the other list.
        let recentRow = app.buttons["builtin.settings"]
        XCTAssertTrue(recentRow.waitForExistence(timeout: 10), "the run action should appear under Recent")

        XCTAssertEqual(
            recentRow.frame.width, resultRowWidth, accuracy: 1,
            "a Recent row and a result row should be the same width"
        )
        XCTAssertEqual(
            recentRow.frame.midX, resultRowMidX, accuracy: 1,
            "a Recent row and a result row should sit on the same centre line"
        )
    }

    // MARK: - The Favorites grid inside the column (issue #265)

    /// The four built-in Actions the grid tests pin, in pin order. Built-ins rather
    /// than seeds: they exist before the first render, need no permission, and are
    /// never pruned by the launch-time reconciliation, so the grid is full on the
    /// first frame and there is no seeding race to wait out.
    private let fourFavorites = [
        "builtin.settings", "builtin.new-reminder", "builtin.new-event", "builtin.new-snippet",
    ]

    @MainActor
    private func favoriteCards(_ app: XCUIApplication, _ ids: [String]) -> [XCUIElement] {
        ids.map { app.buttons["favorite.\($0)"] }
    }

    /// A full grid is **one four-across row** at regular width and the **2×2** that
    /// always shipped at compact — the column count `CommandColumnTests` pins, seen
    /// as the geometry the user actually gets.
    ///
    /// Frames, not counts: four cards exist either way, and the whole finding (audit
    /// F2) is about where they land.
    @MainActor
    func testFullFavoritesGridIsOneRowAtRegularWidthAndTwoByTwoAtCompact() throws {
        let app = launchApp(extraArguments: fourFavorites.flatMap { ["-uitest-pin-favorite", $0] })

        let cards = favoriteCards(app, fourFavorites)
        XCTAssertTrue(cards[0].waitForExistence(timeout: 30), "the pinned Favorites render on Home")
        let frames = cards.map { card -> CGRect in
            XCTAssertTrue(card.exists, "every pinned Favorite should draw a card")
            return card.frame
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            for (index, frame) in frames.enumerated().dropFirst() {
                XCTAssertEqual(
                    frame.midY, frames[0].midY, accuracy: 1,
                    "at regular width all four Favorites should share one row (card \(index) fell off it)"
                )
                XCTAssertGreaterThan(
                    frame.minX, frames[index - 1].maxX,
                    "the cards should run left to right across that row"
                )
            }
            // The row lays out inside the column, not the window: four cards and their
            // three gutters, inside the grid's own 16pt inset off the column's edges.
            let row = frames[3].maxX - frames[0].minX
            XCTAssertEqual(
                row, readableWidth - 2 * gridInset, accuracy: 1,
                "the row should span the column, inset by \(gridInset)pt"
            )
        } else {
            XCTAssertEqual(frames[1].midY, frames[0].midY, accuracy: 1, "compact: the first two share a row")
            XCTAssertEqual(frames[3].midY, frames[2].midY, accuracy: 1, "compact: the last two share a row")
            XCTAssertGreaterThan(frames[2].midY, frames[0].midY, "compact: the grid is 2×2, second row below the first")
            XCTAssertEqual(
                frames[0].width, (app.frame.width - 2 * gridInset - gridSpacing) / 2, accuracy: 1,
                "compact card sizing must be unchanged: half the window, less the insets and the gutter"
            )
        }
    }

    /// The finding itself (audit F2): **one** pinned Favorite draws the same card as
    /// one of four, rather than a slab stretched across the empty slots beside it.
    ///
    /// Asserted as the equality between the two launches instead of a number, because
    /// what was wrong was not the card's width but that the width depended on how
    /// many Actions the user had pinned.
    @MainActor
    func testALoneFavoriteDrawsTheSameCardAsOneOfFour() throws {
        let full = launchApp(extraArguments: fourFavorites.flatMap { ["-uitest-pin-favorite", $0] })
        let firstOfFour = favoriteCards(full, fourFavorites)[0]
        XCTAssertTrue(firstOfFour.waitForExistence(timeout: 30), "the pinned Favorites render on Home")
        let cardInAFullGrid = firstOfFour.frame
        full.terminate()

        let lone = launchApp(extraArguments: ["-uitest-pin-favorite", fourFavorites[0]])
        let onlyCard = favoriteCards(lone, fourFavorites)[0]
        XCTAssertTrue(onlyCard.waitForExistence(timeout: 30), "the single pinned Favorite renders on Home")

        XCTAssertEqual(
            onlyCard.frame.width, cardInAFullGrid.width, accuracy: 1,
            "a lone Favorite should be a card in the row, not a slab that swallows the empty slots"
        )
        XCTAssertEqual(
            onlyCard.frame.minX, cardInAFullGrid.minX, accuracy: 1,
            "and it should sit in the row's first slot, where the first of four sits"
        )
    }
}
