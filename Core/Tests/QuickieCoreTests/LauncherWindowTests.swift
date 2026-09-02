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

    // MARK: - The layout along a resize

    /// **The layout at every width a resize passes through**, out to the floor and back.
    ///
    /// "Non-destructive" is a property of the policy being a *pure function* of the
    /// window — there is no state kept between sizes, so there is nothing for a replayed
    /// drag to catch out. A test that mapped the same function over a width list forwards
    /// and backwards and compared the two would pass by construction and prove nothing.
    ///
    /// What a test *can* do is pin the whole path as a table: the column width and the
    /// grid's column count at each stop the drag makes. A change that gave either a
    /// memory, or made it depend on anything but the window's width and size class,
    /// shows up here as a table that no longer matches. The size class is listed rather
    /// than derived, because deriving it would invent a width threshold this codebase
    /// deliberately does not have — SwiftUI reports the class, and the policy switches
    /// on it (ADR 0039).
    func testTheLayoutAtEveryWidthAResizePassesThrough() {
        let path: [(width: CGFloat, sizeClass: CommandColumn.SizeClass, column: CGFloat, cards: Int)] = [
            (1376, .regular, 680, 4),   // 13" iPad, landscape, full screen
            (1032, .regular, 680, 4),   // …portrait
            (880, .regular, 680, 4),    // the default window
            (686, .regular, 680, 4),    // a half, still regular on a 13" display
            (507, .compact, 507, 2),    // a half on an 11" display: compact, uncapped
            (320, .compact, 320, 2),    // Slide Over, and the declared floor
        ]

        // Out to the floor and back again. Each stop is checked on the way down and on
        // the way up; the round trip is what the criterion is about, and the table is
        // what makes each half of it a statement rather than a tautology.
        for stop in path + path.reversed() {
            XCTAssertEqual(
                CommandColumn.columnWidth(inWindowOf: stop.width, for: stop.sizeClass), stop.column,
                "a \(stop.width)pt \(stop.sizeClass) window should lay out in a \(stop.column)pt column"
            )
            XCTAssertEqual(
                CommandColumn.FavoritesGrid.columnCount(for: stop.sizeClass), stop.cards,
                "a \(stop.width)pt \(stop.sizeClass) window should put \(stop.cards) Favorites across"
            )
        }
    }

    // MARK: - The keyboard, at every tile

    /// **The keyboard lift is right at every tile.** A software keyboard on iPad is a
    /// property of the *display*, not of the window: it is display-wide and docked at
    /// the display's bottom, so at a half or a third it overhangs the window on one or
    /// both sides, and at a quadrant it may not reach the window at all.
    ///
    /// This is the sweep's one behavioural leg — the tiles above only check geometry.
    /// It runs over every display and both orientations, because the binding case is
    /// the *smallest* window with the *tallest* keyboard: an iPad mini's landscape
    /// quadrant is 372pt tall and a docked keyboard is ~353pt, so the window is very
    /// nearly all keyboard, and a lift computed in anything but the window's own space
    /// comes out wrong there first (ADR 0040).
    func testTheBarClearsExactlyWhatTheKeyboardCoversOfEveryTile() {
        for canvas in [Self.thirteenInch, Self.elevenInch, Self.mini] {
            for display in [canvas, CGSize(width: canvas.height, height: canvas.width)] {
                assertTheBarClearsTheKeyboard(on: display)
            }
        }
    }

    /// One display's worth of the sweep above.
    ///
    /// The keyboard's height is the one number here that is measured rather than
    /// derived — iOS sizes it from the display, and a landscape keyboard is the taller
    /// of the two — so it is stated as a fraction of the display's shorter edge, which
    /// tracks the real thing closely enough for the three cases that matter: covering
    /// the whole of a window, part of it, and none of it.
    private func assertTheBarClearsTheKeyboard(on display: CGSize) {
        let keyboardHeight = min(display.width, display.height) * 0.42
        let keyboard = CGRect(
            x: 0, y: display.height - keyboardHeight, width: display.width, height: keyboardHeight
        )
        let safeArea: CGFloat = 20

        // The same tiles as the sweep above, placed where the system puts them: against
        // the display's bottom edge, over the keyboard. Plus a top quadrant, which the
        // keyboard never reaches at all — the case a window-space lift exists to get
        // right, and the one no bottom-anchored tile can show.
        var placements = tiles(on: display).filter { $0.size.width <= display.width }.map { tile in
            (name: tile.name,
             bounds: CGRect(x: 0, y: display.height - tile.size.height,
                            width: tile.size.width, height: tile.size.height))
        }
        placements.append((
            name: "top quadrant",
            bounds: CGRect(x: 0, y: 0, width: display.width / 2, height: display.height / 2)
        ))

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
                "\(Int(display.width))x\(Int(display.height)) \(placement.name): the bar should "
                    + "clear exactly the band the keyboard covers of the window"
            )
        }
    }
}
