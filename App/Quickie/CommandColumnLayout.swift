import SwiftUI
import QuickieCore

/// The launcher's **readable command column** (CONTEXT.md → Readable command column;
/// ADR 0039; issue #260), applied to a view: on a regular-width window the surface
/// clamps to `CommandColumn.readableWidth` and centers; on a compact one it fills the
/// window exactly as it always has.
///
/// The decision itself is Core's (`CommandColumn`), so the width and the
/// regular-vs-compact switch are pinned by `swift test` rather than by whichever view
/// was edited last. All this adds is the two frames the clamp takes in SwiftUI — an
/// inner one that caps, an outer one that centers the cap in the window — and the
/// mapping from SwiftUI's `horizontalSizeClass`.
private struct CommandColumnClamp: ViewModifier {
    /// The window's width class — **not** the device idiom. This is what makes an iPad
    /// resized into Split View revert to the iPhone layout while it is being dragged,
    /// rather than staying a column because the hardware never changed.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// `nil` (a size class SwiftUI hasn't resolved yet) reads as compact: the layout
    /// that ships today is the safe answer for a frame we can't classify.
    private var sizeClass: CommandColumn.SizeClass {
        horizontalSizeClass == .regular ? .regular : .compact
    }

    func body(content: Content) -> some View {
        content
            // The cap. `.infinity` when Core says there is none, so the compact path
            // is the *same* frame that shipped before this modifier existed.
            .frame(maxWidth: CommandColumn.maxWidth(for: sizeClass) ?? .infinity)
            // Centre the capped surface in the window — and, just as importantly, keep
            // this view's own frame full-width, so a background applied outside the
            // clamp (a progressive-blur band, the backdrop) still spans the window.
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Lays this command surface out in the readable command column at regular width;
    /// a no-op at compact width.
    ///
    /// Apply it where the surface would otherwise meet the **window's** edge — outside
    /// its own horizontal padding, not inside it. The column edge stands in for the
    /// window edge, so every surface keeps exactly the inset off it that it keeps off
    /// the screen edge on an iPhone (12pt for a result row's or the input bar's glass,
    /// 16pt for a breadcrumb's crumbs) and the relationship between them is unchanged.
    func commandColumn() -> some View { modifier(CommandColumnClamp()) }
}
