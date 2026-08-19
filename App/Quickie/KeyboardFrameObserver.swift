import SwiftUI
import UIKit

/// Where the keyboard is, **relative to the window the app actually occupies** —
/// the one coordinate space in which the bottom bar's lift is meaningful. On
/// iPad the window is only sometimes the whole display (Split View, Slide Over,
/// Stage Manager, iPadOS 26 free resizing), so every rect here is converted into
/// the host window's own space before it leaves this file (issue #261, ADR 0036).
struct KeyboardWindowFrame {
    /// The keyboard's end-frame in the window's coordinate space. May sit
    /// partly or wholly outside the window — that is exactly what
    /// `KeyboardBarLift.coverage` reads.
    var keyboardFrame: CGRect
    /// The host window's bounds.
    var windowBounds: CGRect
    /// The host window's bottom safe-area inset — the band the bar already sits
    /// in, and so the part of the keyboard's coverage it need not clear.
    var bottomSafeArea: CGFloat
}

/// Reports the keyboard to `RootView` on both of `KeyboardBarLift`'s channels,
/// from inside UIKit where the host window — and therefore the only correct
/// coordinate space — is in hand:
///
/// - **notified**: each `keyboardWillChangeFrame` end-frame, converted from
///   screen coordinates into the window's. Fires at animation start, so the bar
///   can ride the keyboard's own timing.
/// - **live**: the keyboard's current overlap of the window bottom per layout
///   pass, via `UIView.keyboardLayoutGuide` — the one API that follows the
///   keyboard *during* an interactive swipe-dismiss, where
///   `keyboardWillChangeFrame` only fires once the gesture commits.
///
/// Zero-sized and hittest-transparent: install it in a `.background`.
struct KeyboardFrameObserver: UIViewRepresentable {
    /// Called with each keyboard end-frame, resolved against the host window.
    var onKeyboardFrame: (KeyboardWindowFrame) -> Void
    /// Called with the keyboard's current overlap of the *window* bottom, in
    /// points, whenever a layout pass moves the keyboard layout guide — paired
    /// with the window's bottom safe-area inset.
    var onLiveOverlap: (_ overlap: CGFloat, _ bottomSafeArea: CGFloat) -> Void

    func makeUIView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        uiView.onKeyboardFrame = onKeyboardFrame
        uiView.onLiveOverlap = onLiveOverlap
    }

    final class TrackingView: UIView {
        var onKeyboardFrame: ((KeyboardWindowFrame) -> Void)?
        var onLiveOverlap: ((CGFloat, CGFloat) -> Void)?
        private var lastOverlap: CGFloat?

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
                  // Side-by-side on iPad, the *other* app's keyboard posts here
                  // too. It may well cover our window, but nothing of ours is
                  // focused, so it must not move our bar.
                  note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true,
                  let screenFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            // The notification reports the keyboard in **screen** coordinates.
            // `UIWindow.convert(_:from:)` with a nil window is the documented
            // screen → window hop; the explicit `UIWindow?` disambiguates it from
            // `UIView.convert(_:from:)`, which would mean something else entirely.
            let keyboardFrame = window.convert(screenFrame, from: nil as UIWindow?)
            onKeyboardFrame?(KeyboardWindowFrame(
                keyboardFrame: keyboardFrame,
                windowBounds: window.bounds,
                bottomSafeArea: window.safeAreaInsets.bottom
            ))
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let guideTop = convert(keyboardLayoutGuide.layoutFrame, to: window).minY
            let overlap = max(0, window.bounds.height - guideTop)
            guard overlap != lastOverlap else { return }
            lastOverlap = overlap
            onLiveOverlap?(overlap, window.safeAreaInsets.bottom)
        }
    }
}
