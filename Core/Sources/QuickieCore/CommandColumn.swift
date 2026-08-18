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
