import Foundation
#if canImport(CoreGraphics)
// Same reason as `KeyboardBarLift`: Darwin puts `CGSize` in CoreGraphics, while
// swift-corelibs-foundation defines it inside Foundation, so the Linux `swift test`
// run needs no import at all.
import CoreGraphics
#endif

/// How the **Share** secondary action presents (CONTEXT.md → Secondary action; ADR
/// 0017; issue #264, audit finding F9).
///
/// Share is a transient action on **one specific row** — the row the user long-pressed
/// — and on a regular-width window the shape that says so is a popover with its arrow
/// in that row. A sheet rising from the bottom of a 13" iPad severs the connection: by
/// the time it lands, the row that spawned it is behind a dimmed backdrop half a screen
/// away, and nothing on screen says *which* result is about to be shared. On a compact
/// window the popover would be a sheet anyway (that is what the system adapts it to), so
/// compact keeps exactly the presentation that ships today.
///
/// The decision lives here, next to the [[Readable command column]]'s, so both read the
/// window through the *same* size class — `CommandColumn.SizeClass`, mapped from
/// SwiftUI's `horizontalSizeClass` in one place — rather than two views deciding
/// "regular" separately and disagreeing about the same window.
public enum SharePresentation {
    /// The presentation the Share verb takes on a window of a given width.
    public enum Style: Sendable, Equatable {
        /// The sheet that ships today, unchanged.
        case sheet
        /// A popover whose arrow points at the row the verb was invoked from.
        case popoverAnchoredToRow
    }

    /// Which shape Share takes, given the width class and how much **room** the
    /// launcher has to put a popover in — the height of its own content area, which is
    /// the window less whatever the keyboard and the bottom bar have taken.
    ///
    /// Width alone is not enough, and the reason is a property of the thing being
    /// presented. Squeezed below the height it asks for, the iOS share sheet does not
    /// scroll: it **drops** its action list and renders a link preview and an app row,
    /// with no way to reach what is missing. A landscape iPad with the keyboard up, or
    /// a short floating window, leaves exactly that much room. So a popover is offered
    /// only where it fits whole; anywhere else Share falls back to the sheet, which the
    /// system always makes usable — and which is what regular width presented before
    /// the popover existed, so the fallback cannot be a regression on that case.
    ///
    /// The App branches on this to pick the *modifier*, rather than always presenting a
    /// popover and letting `presentationCompactAdaptation` fold it into a sheet. The
    /// adapted sheet looks identical and behaves differently: it carries no `onDismiss`,
    /// and `onDismiss` — the one hook that fires after the surface has actually left —
    /// is what re-arms the input's focus on the way out. "Compact is unchanged" has to
    /// mean the presentation itself, not a lookalike of it.
    public static func style(
        for sizeClass: CommandColumn.SizeClass,
        roomFor availableHeight: CGFloat
    ) -> Style {
        switch sizeClass {
        case .compact:
            return .sheet
        case .regular:
            return availableHeight >= minimumPopoverRoom ? .popoverAnchoredToRow : .sheet
        }
    }

    /// The least room a popover may be offered: the height it asks for, plus the
    /// margins the system keeps between a popover and the edges it is placed against.
    ///
    /// Stated as a sum rather than a bare number so the two move together — raising
    /// `popoverSize.height` without raising this would quietly re-admit the squeeze.
    /// An unmeasured area (zero, before the launcher has laid out) falls below it and
    /// takes the sheet, which is the answer that is never wrong.
    public static let minimumPopoverRoom = popoverSize.height + 2 * popoverMargin

    /// The gap the system leaves between a popover and the edge it is placed against.
    private static let popoverMargin: CGFloat = 12

    /// The popover's content size.
    ///
    /// It is stated rather than derived because the thing inside the popover is a
    /// `UIActivityViewController` — a UIKit controller with no SwiftUI ideal size, so an
    /// unsized popover collapses to nothing. 375×480 is the width of the sheet the same
    /// controller fills on a phone (so its app row and action list lay out at the
    /// proportions it was designed for) at a height that clears the first two rows
    /// without running the full length of the window.
    ///
    /// It applies **only** to the popover: the compact sheet keeps its own full-screen
    /// sizing, and a fixed frame there would strand the activity controller in a 375pt
    /// box in the middle of a phone.
    public static let popoverSize = CGSize(width: 375, height: 480)
}
