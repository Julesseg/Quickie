import Foundation
#if canImport(CoreGraphics)
// CGSize's geometry lives in CoreGraphics on Darwin and inside Foundation itself
// on swift-corelibs-foundation, so the Linux `swift test` run needs no import.
import CoreGraphics
#endif

/// The **launcher window** (CONTEXT.md → Launcher window; ADR 0041; issue #268): the
/// two sizes the app declares to iPadOS about the window it lives in — the floor it
/// may not be dragged below, and the size a fresh window opens at.
///
/// Under iPadOS 26 a window is a continuously resizable rectangle: `UIRequiresFullScreen`
/// is deprecated and ignored, and there is no set of configurations to enumerate. What
/// an app gets to say is exactly these two numbers, and saying nothing — a bare
/// `WindowGroup`, which is what shipped — means the system picks both.
///
/// The two are chosen against the layouts that already exist rather than invented:
///
/// - The **floor** is the smallest window the launcher is still a launcher in. It has
///   to be genuinely small: the system's own tiling produces a quadrant only 372pt
///   tall on an iPad mini, and a floor that refused one would break the very sweep
///   this ticket is about. So it is set at what the content needs and no more.
/// - The **default** is the readable column with a real margin on either side, tall
///   enough for the [[Favorites grid]], a screen of Recents and the bottom bar. A
///   fresh window that opened narrower than `readableWidth` would be compact, and the
///   first thing a new iPad user saw would be the iPhone layout on a 13" canvas.
///
/// Nothing here decides how anything lays *out* — that is `CommandColumn`'s, and the
/// point of stating the sizes beside it is that the two are one policy: the floor is
/// under the column and the default is over it, so a window can be dragged across the
/// whole legal range and only ever land in one of the two layouts that are tested.
///
/// Resizing is **non-destructive** by construction rather than by handling: every
/// layout decision downstream is a pure function of the window's size class, so a
/// window dragged narrow and back wide returns to the layout it left, with nothing
/// torn down and rebuilt in between (a WWDC25 208 requirement, and audit finding F8).
public enum LauncherWindow {
    /// The smallest window the launcher may be resized to.
    ///
    /// **320 wide** is the narrowest canvas iOS has ever handed the compact layout —
    /// the 4" iPhone's, and, not by coincidence, Slide Over's. Below
    /// `CommandColumn.readableWidth` the launcher *is* the iPhone layout (ADR 0039), so
    /// a window at the floor is not a degraded launcher but a familiar one, and nothing
    /// downstream needs a special case to survive it.
    ///
    /// **320 tall** is chosen from *above*, not from below: the system's own tiling
    /// produces a quadrant only 372pt tall on an iPad mini, and a floor that refused
    /// one would break the sweep this policy exists to pass. So the height is set
    /// comfortably under the shortest window the system can hand the app, and it comes
    /// out the same number as the width, which is a coincidence and not a rule.
    /// `LauncherWindowTests` pins that ceiling against the tile table; it deliberately
    /// does *not* derive the floor from the bar, the [[Shelf]] and the
    /// [[Highlighted result]] it has to hold, because those heights are App chrome that
    /// Core does not know and should not restate (`FallbackShelf.Layout` draws the same
    /// line for the same reason).
    ///
    /// Declared rather than left to the system because the system's floor is about
    /// *windows*, not about this app. iPadOS still applies its own floor on top of this
    /// one, so the effective minimum is the larger of the two — declaring ours can only
    /// ever raise it, never talk the system into a window it would otherwise refuse.
    public static let minimumSize = CGSize(width: 320, height: 320)

    /// The size a fresh window opens at: the readable column plus a 100pt margin on
    /// each side, and tall enough that the Favorites grid, a screen of Recents and the
    /// bottom bar are all on screen at once.
    ///
    /// Wider than `CommandColumn.readableWidth` on purpose — a default that landed
    /// compact would open every new window in the iPhone layout, which is the audit
    /// finding this policy exists to answer, arrived at from the other direction.
    ///
    /// It is a *preference*, not a promise: on a display too small to grant it — an
    /// iPad mini is 744pt across in portrait — the system clamps it to what fits, and
    /// the window opens compact there. That is the right outcome and not a shortfall:
    /// the point of the number is that a window is never *needlessly* narrower than the
    /// column, not that every display can show one.
    public static let defaultSize = CGSize(
        width: CommandColumn.readableWidth + 2 * defaultSideMargin,
        height: 1000
    )

    /// The margin the readable column opens with on each side. Enough to read as a
    /// margin rather than as a rounding error: the column has to look chosen at the
    /// window's default size, because that is the size most windows keep.
    public static let defaultSideMargin: CGFloat = 100
}
