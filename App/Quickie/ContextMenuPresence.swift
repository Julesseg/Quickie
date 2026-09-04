import UIKit

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
/// ## Asked of UIKit, not tracked by the app
///
/// The signal used to be the menu's own **preview** view, which SwiftUI
/// instantiated when the menu displayed and tore down when it dismissed. ADR 0042
/// took the lifted preview away — it only ever existed because the system's
/// in-place highlight did not read against translucent Liquid Glass rows, and a
/// row is now a flat opaque material the highlight reads on — and SwiftUI offers
/// no other callback for a `contextMenu`'s presentation.
///
/// So the question is put to UIKit instead, at the instant it is asked: a context
/// menu is a **presented view controller**, and it is already presented by the
/// time the keyboard's departure is posted. That ordering is the whole reason
/// this shape was chosen over watching for the long press that opens the menu —
/// which was tried, and loses the race: the press is only recognised *after* the
/// keyboard has gone, often enough to be useless as a warning.
///
/// It also needs no state, no arming and no expiry. There is nothing to leak,
/// nothing to leave stuck on, and nothing to keep in step with a menu that can be
/// dismissed a dozen ways.
///
/// The one price is that the *kind* of presented controller is read from its class
/// name, which is UIKit's private one. Nothing private is called — this is
/// `type(of:)` on a value UIKit handed us — and it fails soft in the only
/// direction that matters: a renamed class makes this answer `false`, which is
/// the behaviour the app had before issue #58, not a crash. The name is matched
/// loosely (any `…ContextMenu…`) so a variant spelling still lands.
@MainActor
enum ContextMenuPresence {
    /// Whether a context menu is presented anywhere above `window`'s root.
    ///
    /// The whole presentation chain is walked rather than just its first link: the
    /// launcher presents editor and settings sheets, and a menu opened from inside
    /// one is presented *on* it.
    static func isOpen(in window: UIWindow) -> Bool {
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            if String(describing: type(of: presented)).contains("ContextMenu") {
                return true
            }
            controller = presented
        }
        return false
    }
}
