import XCTest
@testable import QuickieCore

/// The readable command column (ADR 0039; issue #260): on a regular-width window
/// the launcher's command surfaces lay out inside one centered, readable column
/// instead of stretching to the window's edges; on a compact one nothing changes.
final class CommandColumnTests: XCTestCase {

    // MARK: - The cap

    /// A regular-width window caps its command surfaces at the readable width —
    /// the whole point of the policy.
    func testRegularWidthCapsAtTheReadableWidth() {
        XCTAssertEqual(CommandColumn.maxWidth(for: .regular), CommandColumn.readableWidth)
    }

    /// A compact window has **no** cap, not a cap that happens to be wider than the
    /// window: the iPhone layout must come out byte-identical to the one that
    /// shipped before this policy existed, and `nil` is what lets the view apply
    /// the same `.infinity` it always did.
    func testCompactWidthIsUncapped() {
        XCTAssertNil(CommandColumn.maxWidth(for: .compact))
    }

    /// The readable width is the number that ships, pinned here so a change to it
    /// is a deliberate edit to a test rather than a silent drift in a view.
    func testReadableWidthIsSixHundredEighty() {
        XCTAssertEqual(CommandColumn.readableWidth, 680)
    }

    // MARK: - The width a surface actually gets

    /// The 13" iPad, full screen: the column, not the window.
    func testWideRegularWindowLaysOutInsideTheColumn() {
        XCTAssertEqual(CommandColumn.columnWidth(inWindowOf: 1376, for: .regular), 680)
    }

    /// A cap never *widens* a surface. A regular-width window narrower than the cap
    /// (the low end of Stage Manager) keeps its own width, so the policy can only
    /// ever subtract.
    func testRegularWindowNarrowerThanTheCapKeepsItsWidth() {
        XCTAssertEqual(CommandColumn.columnWidth(inWindowOf: 620, for: .regular), 620)
    }

    /// Compact: the whole window, at every size — this is the "pixel-identical to
    /// today" half of the policy.
    func testCompactWindowLaysOutEdgeToEdge() {
        for width in [320, 375, 430, 507, 1376] as [CGFloat] {
            XCTAssertEqual(CommandColumn.columnWidth(inWindowOf: width, for: .compact), width)
        }
    }

    // MARK: - What the column heals downstream (audit F10)

    /// The Shelf's peek sizing degenerates on a full-screen iPad: the row is so
    /// much wider than its members need that the solver always lands on the
    /// preferred diameter, the row never scrolls, and the half-button cue that
    /// says "there are more" disappears.
    ///
    /// The column fixes it without the Shelf knowing anything about iPad: its
    /// solver is handed the *column's* width, back inside the envelope the rule
    /// was designed against. Asserted as the pair — same window, same members,
    /// clamped vs not — because the healing is the difference, not the number.
    func testShelfPeekReturnsInsideTheColumnOnAWideWindow() {
        let layout = FallbackShelf.Layout.launcher(preferredDiameter: 52)
        let members = 12
        let window: CGFloat = 1376

        let unclamped = layout.diameter(
            availableWidth: CommandColumn.columnWidth(inWindowOf: window, for: .compact),
            memberCount: members
        )
        XCTAssertEqual(unclamped, layout.preferredDiameter, "the degenerate case: no peek, no scroll")

        let clamped = layout.diameter(
            availableWidth: CommandColumn.columnWidth(inWindowOf: window, for: .regular),
            memberCount: members
        )
        XCTAssertLessThan(clamped, layout.preferredDiameter, "the peek cue is back")
        XCTAssertGreaterThanOrEqual(clamped, layout.minimumDiameter)
    }

    /// A Shelf small enough to fit the column still renders at full size — the
    /// column narrows the row, it does not shrink buttons that had no reason to
    /// shrink.
    func testShelfThatFitsTheColumnKeepsThePreferredDiameter() {
        let layout = FallbackShelf.Layout.launcher(preferredDiameter: 52)
        let diameter = layout.diameter(
            availableWidth: CommandColumn.columnWidth(inWindowOf: 1376, for: .regular),
            memberCount: 4
        )
        XCTAssertEqual(diameter, layout.preferredDiameter)
    }

    // MARK: - The Favorites grid inside the column (issue #265)

    /// Compact width is the 2×2 grid that has always shipped — the "pixel-identical
    /// to today" half of the policy, for the grid this time.
    func testCompactFavoritesGridIsTwoColumns() {
        XCTAssertEqual(CommandColumn.FavoritesGrid.columnCount(for: .compact), 2)
    }

    /// Regular width lays the whole grid out as **one row**: a column count equal to
    /// the Favorites cap is what "4-across" means, and stating it as that equality
    /// rather than as a second `4` is what keeps the two from drifting apart if the
    /// cap ever moves.
    func testRegularFavoritesGridIsOneRowOfTheWholeCap() {
        XCTAssertEqual(
            CommandColumn.FavoritesGrid.columnCount(for: .regular),
            CommandColumn.FavoritesGrid.capacity
        )
    }

    /// A card is a quarter of the column at regular width — the four-across row,
    /// resolved against a full-screen 13" iPad.
    func testRegularCardIsAQuarterOfTheColumn() {
        // (680 − 2×16 inset − 3×10 spacing) ÷ 4
        XCTAssertEqual(
            CommandColumn.FavoritesGrid.cardWidth(inWindowOf: 1376, for: .regular),
            154.5, accuracy: 0.01
        )
    }

    /// The finding this ticket exists for (audit F2): a single pinned Favorite used
    /// to draw a card half the *window* wide — a ~670pt slab for one word and a
    /// glyph. The column count is a function of the size class **alone**, never of
    /// how many Favorites are pinned, so one pin and four pins draw the same card:
    /// the row fills up left to right instead of the cards growing to fill the row.
    func testALoneFavoriteDrawsTheSameCardAsAFullGrid() {
        let card = CommandColumn.FavoritesGrid.cardWidth(inWindowOf: 1376, for: .regular)
        XCTAssertLessThan(
            card, CommandColumn.readableWidth / 3,
            "one Favorite should be a card in a four-across row, not a slab"
        )
    }

    /// Compact card sizing is untouched at every iPhone width: half the window, less
    /// the grid's own inset and the gutter between the two cards.
    func testCompactCardIsHalfTheWindowAsItAlwaysWas() {
        for window in [320, 375, 393, 430] as [CGFloat] {
            XCTAssertEqual(
                CommandColumn.FavoritesGrid.cardWidth(inWindowOf: window, for: .compact),
                (window - 32 - 10) / 2, accuracy: 0.01
            )
        }
    }

    /// The grid is capped by the column like every other command surface: a card on
    /// a 13" iPad is narrower than one on an iPhone, not wider — four cards inside
    /// 680pt rather than four cards spread over 1,376.
    func testTheGridIsCappedByTheColumnNotTheWindow() {
        let iPad = CommandColumn.FavoritesGrid.cardWidth(inWindowOf: 1376, for: .regular)
        let iPhone = CommandColumn.FavoritesGrid.cardWidth(inWindowOf: 393, for: .compact)
        XCTAssertLessThan(iPad, iPhone)
    }
}
