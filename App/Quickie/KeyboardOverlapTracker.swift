import SwiftUI
import UIKit

/// Reports the keyboard's **live** screen overlap frame-by-frame while an
/// interactive swipe-dismiss drags it (issue #64 — the input must follow the
/// keyboard exactly). `keyboardWillChangeFrameNotification` is silent for the
/// whole drag — it fires only when the gesture ends — so this view bridges
/// UIKit's `keyboardLayoutGuide`, the one thing that tracks the keyboard's top
/// edge under the finger: a hidden follower is pinned to the guide, every guide
/// move lays this view out again, and each pass reports the fresh overlap.
///
/// Scheduled keyboard animations (appear, the post-release settle, a context
/// menu's resign) are deliberately **not** reported: their layout passes run
/// inside UIKit's animation transaction (`inheritedAnimationDuration > 0`) and
/// carry only the end value, and they are the will-change notification's job —
/// reporting them too would double-drive the lift.
struct KeyboardOverlapTracker: UIViewRepresentable {
    /// Called with the keyboard's current overlap, measured from the window
    /// bottom, once per interactive frame in which it changed.
    var onSample: (CGFloat) -> Void

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onSample = onSample
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {
        uiView.onSample = onSample
    }

    final class TrackerView: UIView {
        var onSample: ((CGFloat) -> Void)?

        /// Pinned to `keyboardLayoutGuide.topAnchor`: its only purpose is to
        /// make every keyboard move dirty this view's layout.
        private let follower = UIView()
        private var lastOverlap: CGFloat?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            follower.isHidden = true
            follower.translatesAutoresizingMaskIntoConstraints = false
            addSubview(follower)
            NSLayoutConstraint.activate([
                follower.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                follower.leadingAnchor.constraint(equalTo: leadingAnchor),
                follower.widthAnchor.constraint(equalToConstant: 1),
                follower.heightAnchor.constraint(equalToConstant: 1),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            // A pass inside an animation transaction is a *scheduled* keyboard
            // move — the notification path animates the bar for those.
            guard UIView.inheritedAnimationDuration == 0 else { return }
            // The guide's top in window coordinates → overlap from the window
            // bottom, whole points so sub-point layout noise doesn't churn
            // SwiftUI once per frame for an invisible difference.
            let guideTop = follower.convert(CGPoint.zero, to: window).y
            let overlap = (window.bounds.height - guideTop).rounded()
            guard overlap != lastOverlap else { return }
            lastOverlap = overlap
            onSample?(overlap)
        }
    }
}
