import XCTest
@testable import QuickieCore

/// The launcher window (ADR 0041; issue #268; audit finding F8): the floor the window
/// may not be dragged below, the size a fresh one opens at, and the sweep across every
/// size iPadOS 26's tiling actually produces.
final class LauncherWindowTests: XCTestCase {

    // MARK: - The two declared sizes

    /// The floor, pinned here so a change to it is a deliberate edit rather than a
    /// number drifting in a scene modifier.
    func testMinimumSizeIsTheSmallestUsableLauncher() {
        XCTAssertEqual(LauncherWindow.minimumSize, CGSize(width: 320, height: 320))
    }

    /// The default is the readable column plus a real margin on each side.
    func testDefaultSizeIsTheColumnPlusItsMargins() {
        XCTAssertEqual(
            LauncherWindow.defaultSize.width,
            CommandColumn.readableWidth + 2 * LauncherWindow.defaultSideMargin
        )
        XCTAssertEqual(LauncherWindow.defaultSize, CGSize(width: 880, height: 1000))
    }

    // MARK: - How the two sizes sit either side of the column

    /// A window at the floor is **narrower than the column**, so it can only ever be
    /// the compact layout: the cap can never exceed the window it is applied to, and
    /// the smallest legal window is the iPhone layout the app has always shipped
    /// rather than a squeezed variant of the iPad one.
    func testTheFloorSitsBelowTheColumn() {
        XCTAssertLessThan(LauncherWindow.minimumSize.width, CommandColumn.readableWidth)
        XCTAssertEqual(
            CommandColumn.columnWidth(inWindowOf: LauncherWindow.minimumSize.width, for: .compact),
            LauncherWindow.minimumSize.width,
            "at the floor the launcher lays out edge to edge, exactly as it does on an iPhone"
        )
    }

    /// A fresh window is **wider than the column**, and by enough that the column
    /// reads as a column: a default that opened compact would put every new iPad
    /// window into the iPhone layout, which is the finding the column exists to fix.
    func testAFreshWindowShowsTheColumnWithMarginsOnBothSides() {
        let width = LauncherWindow.defaultSize.width
        XCTAssertEqual(CommandColumn.columnWidth(inWindowOf: width, for: .regular), CommandColumn.readableWidth)
        XCTAssertEqual(
            (width - CommandColumn.readableWidth) / 2,
            LauncherWindow.defaultSideMargin,
            "the column should open centred, with the declared margin on each side"
        )
    }

    // MARK: - The odd-size sweep (iPadOS 26 tiling)

    /// One size the system's tiling can hand the app, named as the user would name it.
    private struct Tile {
        let name: String
        let size: CGSize
    }

    /// A display's usable canvas, in points, for the two iPads the audit covers.
    private static let thirteenInch = CGSize(width: 1032, height: 1376)
    private static let elevenInch = CGSize(width: 834, height: 1210)
    /// The smallest iPad, and so the one that produces the smallest tile of all — the
    /// binding constraint on how high the floor may be set.
    private static let mini = CGSize(width: 744, height: 1133)

    /// The sizes the ticket's QA sweep walks on one display, in both orientations: the
    /// halves it snaps a window to against an edge, the quadrants it snaps to against a
    /// corner, and Slide Over — which is not a fraction of anything but a fixed 320pt
    /// panel, and so the narrowest canvas the system ever hands an app.
    ///
    /// Thirds are **landscape only**: a third of a portrait iPad is 278–344pt, at or
    /// under Slide Over's own width, and the system does not offer a split that narrow
    /// there. Listing one anyway would put a size in the sweep that no user can reach
    /// and make the floor below answer a question nobody asked.
    ///
    /// Derived from the display rather than transcribed, so the sweep reads as the
    /// fractions it is and a third display can be added by adding its size.
    private func tiles(on display: CGSize) -> [Tile] {
        [CGSize(width: display.width, height: display.height),
         CGSize(width: display.height, height: display.width)].flatMap { canvas -> [Tile] in
            let landscape = canvas.width > canvas.height
            let orientation = landscape ? "landscape" : "portrait"
            return [
                Tile(name: "\(orientation) full screen", size: canvas),
                Tile(name: "\(orientation) half", size: CGSize(width: canvas.width / 2, height: canvas.height)),
                Tile(name: "\(orientation) quadrant", size: CGSize(width: canvas.width / 2, height: canvas.height / 2)),
                Tile(name: "\(orientation) Slide Over", size: CGSize(width: 320, height: canvas.height)),
            ] + (landscape ? [
                Tile(name: "\(orientation) third", size: CGSize(width: canvas.width / 3, height: canvas.height)),
                Tile(name: "\(orientation) two thirds", size: CGSize(width: canvas.width * 2 / 3, height: canvas.height)),
            ] : [])
        }
    }

    private var everyTile: [Tile] {
        tiles(on: Self.thirteenInch) + tiles(on: Self.elevenInch) + tiles(on: Self.mini)
    }

    /// **No tile is below the floor.** The floor is what the app declares usable, so a
    /// tile under it would be a size the system can produce and the app has told it it
    /// may not — a window the user can reach through tiling and not by dragging. The
    /// sweep's precondition, and the reason the floor is not set anywhere roomier: an
    /// iPad mini's landscape quadrant is 372pt tall, and that is the ceiling on it.
    func testEverySystemTileIsAtOrAboveTheDeclaredFloor() {
        for tile in everyTile {
            XCTAssertGreaterThanOrEqual(
                tile.size.width, LauncherWindow.minimumSize.width,
                "\(tile.name) is narrower than the declared floor"
            )
            XCTAssertGreaterThanOrEqual(
                tile.size.height, LauncherWindow.minimumSize.height,
                "\(tile.name) is shorter than the declared floor"
            )
        }
    }

    /// **The column never overflows a tile.** A cap can only subtract, so at every
    /// tile the command surfaces come out at the tile's own width or at the column's,
    /// whichever is smaller — never wider than the window they are drawn in, which is
    /// what a clipped input bar would look like.
    func testTheColumnNeverOverflowsATileAtEitherSizeClass() {
        for tile in everyTile {
            for sizeClass in [CommandColumn.SizeClass.compact, .regular] {
                let column = CommandColumn.columnWidth(inWindowOf: tile.size.width, for: sizeClass)
                XCTAssertLessThanOrEqual(
                    column, tile.size.width,
                    "\(tile.name) at \(sizeClass): the column ran wider than the window"
                )
                XCTAssertGreaterThan(column, 0, "\(tile.name) at \(sizeClass): the column collapsed")
            }
        }
    }

    /// **A lone Favorite is a card at every tile.** The grid divides the column it is
    /// in, so the narrowest tile is where a card would collapse if the count and the
    /// insets ever stopped fitting — the one arithmetic in the layout policy that a
    /// small window can break.
    func testFavoriteCardsStayPositivelySizedAtEveryTile() {
        for tile in everyTile {
            for sizeClass in [CommandColumn.SizeClass.compact, .regular] {
                XCTAssertGreaterThan(
                    CommandColumn.FavoritesGrid.cardWidth(inWindowOf: tile.size.width, for: sizeClass), 0,
                    "\(tile.name) at \(sizeClass): a Favorite card came out with no width"
                )
            }
        }
    }

    // MARK: - Non-destructive resizing

    /// **Resizing is non-destructive**: dragging a window narrow and back wide returns
    /// the layout it left, rather than a rebuilt approximation of it.
    ///
    /// Asserted as the property that makes it true — every layout decision is a pure
    /// function of the window, with no state carried between sizes — by replaying one
    /// resize forwards and then backwards and demanding the same answer at each width
    /// on the way back. A policy that remembered anything about the widths it had been
    /// through would disagree with itself here.
    func testResizingBackToAWidthRestoresTheLayoutItLeft() {
        let drag: [CGFloat] = [1376, 1032, 880, 686, 507, 320]
        let sizeClass: (CGFloat) -> CommandColumn.SizeClass = { $0 >= 680 ? .regular : .compact }

        let outbound = drag.map { width in
            (CommandColumn.columnWidth(inWindowOf: width, for: sizeClass(width)),
             CommandColumn.FavoritesGrid.columnCount(for: sizeClass(width)))
        }
        let inbound = drag.reversed().map { width in
            (CommandColumn.columnWidth(inWindowOf: width, for: sizeClass(width)),
             CommandColumn.FavoritesGrid.columnCount(for: sizeClass(width)))
        }

        for (index, expected) in outbound.enumerated() {
            let restored = inbound[inbound.count - 1 - index]
            XCTAssertEqual(restored.0, expected.0, "column width at \(drag[index])pt was not restored")
            XCTAssertEqual(restored.1, expected.1, "Favorites column count at \(drag[index])pt was not restored")
        }
    }

    // MARK: - The keyboard, at every tile

    /// **The keyboard lift is right at every tile.** A software keyboard on iPad is a
    /// property of the *display*, not of the window: it is display-wide and docked at
    /// the display's bottom, so at a half or a third it overhangs the window on one or
    /// both sides, and at a quadrant it may not reach the window at all.
    ///
    /// This is the sweep's one behavioural leg — the tiles above only check geometry.
    /// It walks each tile placed at the display's bottom-left corner (where the system
    /// puts a left-hand tile) and asserts the bar clears exactly the band the keyboard
    /// covers *of that window*, which is the whole of ADR 0040 seen at every size the
    /// system can produce.
    func testTheBarClearsExactlyWhatTheKeyboardCoversOfEachTile() {
        // The 13" display, landscape, with a docked keyboard across its bottom.
        let display = CGSize(width: Self.thirteenInch.height, height: Self.thirteenInch.width)
        let keyboardHeight: CGFloat = 353
        let keyboard = CGRect(
            x: 0, y: display.height - keyboardHeight, width: display.width, height: keyboardHeight
        )
        let safeArea: CGFloat = 20

        // Each tile as the system places it: the bottom-anchored ones sit on the
        // display's bottom edge, over the keyboard; the top quadrant does not reach it
        // at all, which is the case a window-space lift exists to get right.
        let placements: [(name: String, bounds: CGRect)] = [
            ("full screen", CGRect(origin: .zero, size: display)),
            ("half", CGRect(x: 0, y: 0, width: display.width / 2, height: display.height)),
            ("third", CGRect(x: 0, y: 0, width: display.width / 3, height: display.height)),
            ("two thirds", CGRect(x: 0, y: 0, width: display.width * 2 / 3, height: display.height)),
            ("Slide Over", CGRect(x: display.width - 320, y: 0, width: 320, height: display.height)),
            ("bottom quadrant", CGRect(
                x: 0, y: display.height / 2, width: display.width / 2, height: display.height / 2
            )),
            ("top quadrant", CGRect(x: 0, y: 0, width: display.width / 2, height: display.height / 2)),
        ]

        for placement in placements {
            let geometry = KeyboardBarLift.Geometry(
                keyboardFrame: keyboard, windowBounds: placement.bounds, bottomSafeArea: safeArea
            )
            // What the keyboard covers *of this window* — zero for a tile that ends
            // above it, the keyboard's own height for one that runs to the bottom.
            let covered = max(0, placement.bounds.maxY - max(keyboard.minY, placement.bounds.minY))
            let change = KeyboardBarLift.notified(
                geometry,
                isLocalKeyboard: true,
                contextMenuOpen: false,
                isListScrolling: false,
                usesKeyboardlessControl: false
            )
            XCTAssertEqual(
                change, .animateWithKeyboard(inset: max(0, covered - safeArea)),
                "\(placement.name): the bar should clear exactly the band the keyboard covers of the window"
            )
        }
    }
}
