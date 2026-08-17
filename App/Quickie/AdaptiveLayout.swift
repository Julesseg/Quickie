import SwiftUI

/// PROTOTYPE (iPad UI audit): clamp a full-width iPhone surface to a readable,
/// centered command column when the window is regular-width (full-screen iPad,
/// large Stage Manager windows). Compact width — iPhone, iPad Split View —
/// keeps the stretch-to-fill behavior unchanged.
///
/// 680pt tracks UIKit's readable-content guide on large iPads. Size class, not
/// device idiom, is deliberately the switch: a half-screen iPad window is
/// compact and must keep the iPhone layout.
struct CommandColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: hSize == .regular ? 680 : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Clamps this surface to the centered readable command column on
    /// regular-width windows; no-op at compact width.
    func commandColumn() -> some View { modifier(CommandColumn()) }
}
