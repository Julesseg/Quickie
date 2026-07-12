import SwiftUI
import UIKit

/// Reports the keyboard's **live** overlap of the screen bottom, per layout pass,
/// via `UIView.keyboardLayoutGuide` — the one API that follows the keyboard
/// *during* an interactive swipe-dismiss, where `keyboardWillChangeFrame` only
/// fires once the gesture commits. `RootView` feeds each sample to
/// `KeyboardBarLift.dragged`, which ignores everything that isn't a drag, so the
/// notified channel keeps owning ordinary show/hide.
///
/// Zero-sized and hittest-transparent: install it in a `.background`.
struct KeyboardFrameObserver: UIViewRepresentable {
    /// Called with the keyboard's current overlap of the screen bottom, in
    /// points, whenever a layout pass moves the keyboard layout guide.
    var onOverlapChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        uiView.onOverlapChange = onOverlapChange
    }

    final class TrackingView: UIView {
        var onOverlapChange: ((CGFloat) -> Void)?
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
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let guideTop = convert(keyboardLayoutGuide.layoutFrame, to: window).minY
            let overlap = max(0, window.bounds.height - guideTop)
            guard overlap != lastOverlap else { return }
            lastOverlap = overlap
            onOverlapChange?(overlap)
        }
    }
}
