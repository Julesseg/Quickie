import Foundation

/// The **readable command column** (CONTEXT.md → Readable command column; ADR 0039;
/// issue #260): the single centered, readable-width column the launcher's command
/// surfaces — the input bar, the [[Shelf]], the paste chip, the [[Result list]], the
/// [[Search Files context]]'s rows, and a capture's breadcrumb crumbs — lay out inside
/// on a regular-width window, instead of stretching to the edges of a 13" iPad.
///
/// Two decisions, and the split between them is the policy:
///
/// - **Whether there is a cap at all** is decided by the window's *size class*, never
///   by the device idiom. A half-screen iPad window is compact and must come out
///   pixel-identical to the iPhone, and the same window dragged wide must become a
///   column without anything being torn down and rebuilt — an idiom check gets both of
///   those wrong, permanently, because the idiom never changes.
/// - **What the cap is** is `readableWidth`, and it lives here rather than beside a
///   view so every surface that opts in is clamped to the *same* number. A column the
///   results share but the input bar misses by 8pt is worse than no column at all: the
///   whole effect is that one edge runs down the screen through every surface.
///
/// Nothing here knows about SwiftUI, so the rule is exercised by `swift test` rather
/// than only by the eye. The App reads `maxWidth(for:)` to build the clamp; `nil` means
/// "no cap", which is what keeps the compact path byte-identical to the layout that
/// shipped before this policy existed rather than merely equivalent to it.
///
/// Only *content* clamps. The full-bleed layers behind it — the mesh backdrop, the
/// progressive-blur bands under the breadcrumb and the Favorites band — still span the
/// whole window, because a blur band that stopped at the column would draw the column's
/// edges as two hard lines (ADR 0010: depth is the glass's job, not an outline's).
public enum CommandColumn {
    /// The window's horizontal size class, as this policy needs it — the App maps
    /// SwiftUI's `horizontalSizeClass` onto it, and an *unknown* class maps to
    /// `.compact`, because the layout that ships today is the safe answer.
    public enum SizeClass: Sendable, Equatable {
        /// iPhone, iPad Split View, a narrow Stage Manager window.
        case compact
        /// A full-screen iPad, or a Stage Manager window wide enough to be regular.
        case regular
    }

    /// How wide the column gets: ~680pt, tracking UIKit's readable-content guide,
    /// which tops out in the same neighbourhood for the same reason — a line of text
    /// (and a row whose label and glyph sit at its two ends) stops being comfortable to
    /// read, or to connect, much past it.
    public static let readableWidth: CGFloat = 680

    /// The cap a command surface lays out under, or `nil` when it fills the window.
    public static func maxWidth(for sizeClass: SizeClass) -> CGFloat? {
        switch sizeClass {
        case .compact: return nil
        case .regular: return readableWidth
        }
    }

    /// The width a command surface actually gets in a window `windowWidth` across.
    ///
    /// This is the same decision as `maxWidth(for:)` — it is *defined* by it — resolved
    /// against a real window, which is what makes it testable against the *downstream*
    /// rules that measure a row and size themselves from it (the [[Shelf]]'s peek
    /// solver, the breadcrumb's equal-share crumb widths). A cap can only ever
    /// subtract: a regular-width window narrower than the cap keeps its own width.
    ///
    /// It models what SwiftUI does with the cap rather than being the call the App
    /// makes — the App hands `maxWidth(for:)` straight to `.frame(maxWidth:)`, since
    /// a view has no business knowing the window's width. `CommandColumnUITests`
    /// closes that loop on a real iPad, where the row measures the column exactly.
    public static func columnWidth(inWindowOf windowWidth: CGFloat, for sizeClass: SizeClass) -> CGFloat {
        guard let cap = maxWidth(for: sizeClass) else { return windowWidth }
        return min(windowWidth, cap)
    }
}

extension CommandColumn {
    /// How [[Home]]'s **Favorites grid** lays its cards out inside the column
    /// (CONTEXT.md → Favorites grid; issue #265, audit finding F2). ADR 0039 clamped
    /// the grid as a *container* and deliberately left this open: a grid can sit
    /// inside the column and still be laid out wrong within it.
    ///
    /// It was wrong in exactly that way. The grid was two flexible columns at every
    /// width, so on a full-screen iPad four cards took two rows of ~330pt slabs —
    /// each one a badge at the far left and a glyph at the far right with a word
    /// between them, the same eye-travel the column exists to end — and a *single*
    /// pinned Favorite drew one card half the grid wide, a shape nothing else in the
    /// app has.
    ///
    /// The decision is that the **column count** is a function of the window's size
    /// class and of nothing else — least of all of how many Favorites are pinned. A
    /// grid whose columns tracked its item count would make one pin a slab all over
    /// again; instead the row is fixed and fills left to right, so one card and four
    /// cards are the same card. At regular width the count is the Favorites cap
    /// itself, which is what makes the whole grid a single row: four across, one row
    /// of the launcher's pinned Actions above the Recent list, no second row of air.
    public enum FavoritesGrid {
        /// How many Favorites the grid holds (CONTEXT.md → Favorite): four, which a
        /// fifth pin is refused for. It is the same number as the regular-width
        /// column count *by construction* — "the whole grid is one row" is the
        /// decision, so the cap moving moves the row with it.
        ///
        /// This is the app's one Favorites cap: the pin toggle (`SignalsStore`) and
        /// the widgets' four cells (`FavoritesWidgetSnapshot.capacity`, which the
        /// widget grid chains from) both read it here, since a widget that mirrors
        /// the grid (ADR 0025) must not merely happen to agree with it.
        public static let capacity = 4

        /// The gutter between cards, both between columns and between rows.
        public static let spacing: CGFloat = 10

        /// The grid's own inset off the edge it lays out against — the window's at
        /// compact width, the column's at regular (ADR 0039: the column edge stands
        /// in for the window edge, and each surface keeps the inset it always had).
        public static let horizontalInset: CGFloat = 16

        /// How many cards lay out across one row.
        public static func columnCount(for sizeClass: SizeClass) -> Int {
            switch sizeClass {
            case .compact: return 2
            case .regular: return capacity
            }
        }

        /// How wide one Favorite card comes out in a window `windowWidth` across.
        ///
        /// Like `columnWidth(inWindowOf:for:)`, this models what SwiftUI's `LazyVGrid`
        /// does with the flexible columns the App hands it rather than being a
        /// second implementation of it — the App passes the count, the spacing and
        /// the inset from here, so the arithmetic is the same arithmetic. What it
        /// buys is a card *size* `swift test` can hold: that a lone pin is a card
        /// and not a slab is a number, and this is the number.
        public static func cardWidth(inWindowOf windowWidth: CGFloat, for sizeClass: SizeClass) -> CGFloat {
            let columns = CGFloat(columnCount(for: sizeClass))
            let content = columnWidth(inWindowOf: windowWidth, for: sizeClass)
                - 2 * horizontalInset
                - (columns - 1) * spacing
            return content / columns
        }
    }
}
