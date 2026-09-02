import SwiftUI
import UIKit
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

    private var sizeClass: CommandColumn.SizeClass { .init(horizontalSizeClass) }

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

    /// Lays a pushed [[Management page]]'s `List`/`Form` out in the same readable
    /// column (CONTEXT.md → Management page, Readable command column; ADR 0039;
    /// issue #266) at regular width; a no-op at compact width.
    ///
    /// Apply it to the whole scroll view, not to a row: a grouped list owns the
    /// margins between its rows and the edge it is handed, so narrowing the *list*
    /// carries every row, header, footer and separator in with it and keeps them
    /// related exactly as they are on an iPhone. Narrowing the rows instead would
    /// leave the section insets measured against the window.
    func managementColumn() -> some View { modifier(ManagementColumnClamp()) }
}

/// The [[Management page]] flavour of the clamp (issue #266, audit finding F6): the
/// same column, plus the page's own background put back across the window.
///
/// A management page has no [[Living backdrop]] behind it — the list *is* the page's
/// background, so clamping it alone would leave the two margins beside the column
/// showing whatever the navigation container happens to paint. Restating the grouped
/// background outside the clamp is the same division ADR 0039 already draws for the
/// launcher: content clamps, the full-bleed layer behind it does not. It is the
/// system colour a grouped `List` paints for itself, so at compact width the list
/// covers it completely and the page is unchanged.
private struct ManagementColumnClamp: ViewModifier {
    func body(content: Content) -> some View {
        content
            .commandColumn()
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

extension CommandColumn.SizeClass {
    /// SwiftUI's horizontal size class, as the layout policy takes it. One mapping,
    /// shared by the clamp and by every surface that shapes itself differently inside
    /// the column (Home's Favorites grid picks its column count from it), because two
    /// views reading the environment through two different conditions is how the same
    /// window ends up regular for one surface and compact for the one beside it.
    ///
    /// `nil` — a class SwiftUI hasn't resolved yet — reads as **compact**: the layout
    /// that ships today is the safe answer for a frame we can't classify.
    init(_ horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular ? .regular : .compact
    }
}
