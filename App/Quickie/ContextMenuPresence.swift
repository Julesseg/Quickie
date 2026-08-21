import SwiftUI

/// Whether a row's long-press context menu is on screen right now.
///
/// The bottom bar's keyboard lift needs this and cannot infer it. When a menu
/// opens, UIKit drops the keyboard, and the `keyboardWillChangeFrame` it posts
/// is **byte-identical** to the one an explicit dismissal posts — same end
/// frame, same duration and curve, same `isLocal`, and the text field keeps
/// first responder in both. Window count and key-window state don't move either.
/// So the lift is told, rather than left to guess: a menu-driven drop **holds**
/// the inset so the list stays still under the menu (issue #58), and every other
/// drop releases it so the bar returns to the window bottom (issue #261).
///
/// The signal is the menu's own **preview** view, which SwiftUI instantiates
/// when the menu displays and tears down when it dismisses — see
/// `View.resultContextMenu`, the single place every menu in the app is built.
/// A count rather than a flag: two rows can overlap by a frame during the
/// hand-off from one menu to the next, and a plain bool would land on `false`.
///
/// A shared instance because there is only ever one menu, and because the
/// keyboard observer must read it from a UIKit notification rather than from
/// SwiftUI's view graph — the same reason `refocusInput` asks UIKit directly
/// instead of trusting `FocusState`.
@MainActor
final class ContextMenuPresence {
    static let shared = ContextMenuPresence()

    private var openCount = 0

    /// Whether a context menu is currently displayed.
    var isOpen: Bool { openCount > 0 }

    func menuAppeared() {
        openCount += 1
    }

    func menuDisappeared() {
        openCount = max(0, openCount - 1)
    }
}
