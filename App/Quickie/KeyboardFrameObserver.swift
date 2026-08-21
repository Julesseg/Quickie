import QuickieCore
import SwiftUI
import UIKit

/// Reports the keyboard to `RootView` on both of `KeyboardBarLift`'s channels,
/// from inside UIKit where the host window — and therefore the only correct
/// coordinate space — is in hand:
///
/// - **notified**: each `keyboardWillChangeFrame` end-frame, converted from
///   screen coordinates into the window's and paired with that window's bounds
///   and bottom inset (issue #261, ADR 0040). Fires at animation start, so the
///   bar can ride the keyboard's own timing.
/// - **live**: the keyboard's current overlap of the window bottom per layout
///   pass, via `UIView.keyboardLayoutGuide` — the one API that follows the
///   keyboard *during* an interactive swipe-dismiss, where
///   `keyboardWillChangeFrame` only fires once the gesture commits. It is also
///   the only signal that the **window** changed shape under a stationary
///   keyboard (a Split View divider drag, a Stage Manager resize, a rotation),
///   which the keyboard itself never posts, so each sample says whether it
///   arrived for that reason.
///
/// Zero-sized and hittest-transparent: install it in a `.background`.
struct KeyboardFrameObserver: UIViewRepresentable {
    /// Called with each keyboard end-frame, resolved against the host window,
    /// plus the two pieces of state that only mean anything read at the
    /// notification's own instant: whether the keyboard is this app's own (side
    /// by side on iPad, the other app's posts here too), and whether a row's
    /// long-press menu is what put it away.
    var onKeyboardFrame: (
        KeyboardBarLift.Geometry,
        _ isLocalKeyboard: Bool,
        _ contextMenuOpen: Bool
    ) -> Void
    /// Called with the keyboard's current overlap of the *window* bottom, in
    /// points, whenever a layout pass moves the keyboard layout guide relative
    /// to the window — paired with the window's bottom safe-area inset, and with
    /// whether this pass is one where the *window* itself changed shape.
    var onLiveOverlap: (
        _ overlap: CGFloat,
        _ bottomSafeArea: CGFloat,
        _ windowChangedShape: Bool
    ) -> Void

    func makeUIView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        uiView.onKeyboardFrame = onKeyboardFrame
        uiView.onLiveOverlap = onLiveOverlap
    }

    final class TrackingView: UIView {
        var onKeyboardFrame: ((KeyboardBarLift.Geometry, Bool, Bool) -> Void)?
        var onLiveOverlap: ((CGFloat, CGFloat, Bool) -> Void)?
        private var lastOverlap: CGFloat?
        private var lastWindowBounds: CGRect?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            // The guide only tracks the keyboard once a constraint references it;
            // pin a hidden, zero-size probe so every keyboard move dirties our
            // layout and `layoutSubviews` sees each frame of an interactive drag.
            let probe = UIView()
            probe.isHidden = true
            probe.translatesAutoresizingMaskIntoConstraints = false
            addSubview(probe)
            NSLayoutConstraint.activate([
                probe.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                probe.leadingAnchor.constraint(equalTo: keyboardLayoutGuide.leadingAnchor),
                probe.widthAnchor.constraint(equalToConstant: 0),
                probe.heightAnchor.constraint(equalToConstant: 0),
            ])
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        @objc private func keyboardWillChangeFrame(_ note: Notification) {
            guard let window,
                  let screenFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            // The notification reports the keyboard in **screen** coordinates.
            // `UIWindow.convert(_:from:)` with a nil window is the documented
            // screen → window hop; the explicit `UIWindow?` disambiguates it from
            // `UIView.convert(_:from:)`, which would mean something else entirely.
            let geometry = KeyboardBarLift.Geometry(
                keyboardFrame: window.convert(screenFrame, from: nil as UIWindow?),
                windowBounds: window.bounds,
                bottomSafeArea: window.safeAreaInsets.bottom
            )
            let isLocal = note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true
            // Read *now*: by a later runloop turn the menu that caused this drop
            // may already have closed. Nothing in the notification itself tells a
            // menu-driven drop from a real dismissal — see `ContextMenuPresence`.
            onKeyboardFrame?(geometry, isLocal, ContextMenuPresence.shared.isOpen)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let bounds = window.bounds
            let bottomSafeArea = window.safeAreaInsets.bottom
            let guideTop = convert(keyboardLayoutGuide.layoutFrame, to: window).minY
            let overlap = max(0, bounds.height - guideTop)
            // A window reshaped under a stationary keyboard covers a different
            // band of it, and the keyboard posts nothing to say so — this pass is
            // the only notice. A window's shape is its **bounds** alone: the
            // bottom safe-area inset can move for reasons that are not a reshape
            // at all, and re-seating the bar unanimated on those would fight the
            // notified channel that owns them. The first layout is not a reshape.
            let changedShape = lastWindowBounds.map { $0 != bounds } ?? false
            lastWindowBounds = bounds
            guard changedShape || overlap != lastOverlap else { return }
            lastOverlap = overlap
            onLiveOverlap?(overlap, bottomSafeArea, changedShape)
        }
    }
}
