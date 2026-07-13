import SwiftUI
import UIKit

/// A **raw progressive blur**: the backdrop's blur *radius* ramps from
/// `maxRadius` at the top edge down to zero at the bottom, with no material
/// tint at all — the blur alone separates the status area from the content
/// scrolling under it, and fading the radius (not the opacity) means there is
/// no washed band and no hard edge, just content coming smoothly into focus.
///
/// SwiftUI has no backdrop-blur primitive (only tinted materials), so this
/// reaches into `UIVisualEffectView`: the tint layers are hidden and the
/// backdrop layer's gaussian filter is replaced with CoreAnimation's
/// `variableBlur` filter driven by a vertical alpha-gradient mask. The filter
/// is resolved by name at runtime (it has no public constructor); if that
/// lookup ever stops working the view degrades to a *uniform* untinted blur
/// over its frame rather than crashing or re-tinting.
struct VariableBlur: UIViewRepresentable {
    /// The blur radius at the fully-blurred (top) edge.
    var maxRadius: CGFloat = 20

    func makeUIView(context: Context) -> VariableBlurUIView {
        VariableBlurUIView(maxRadius: maxRadius)
    }

    func updateUIView(_ uiView: VariableBlurUIView, context: Context) {}
}

final class VariableBlurUIView: UIVisualEffectView {
    private let maxRadius: CGFloat

    init(maxRadius: CGFloat) {
        self.maxRadius = maxRadius
        super.init(effect: UIBlurEffect(style: .regular))
        // Everything above the backdrop (the first subview) is the material's
        // tint stack — hiding it leaves only the raw blur.
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
        applyVariableBlur()
        // A light/dark switch makes UIVisualEffectView rebuild its backdrop
        // filters (restoring the uniform gaussian) — reapply ours after.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: VariableBlurUIView, _) in
            view.applyVariableBlur()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Match the backdrop's rasterization scale to the screen so the
        // faintly-blurred region doesn't shimmer with pixelation.
        guard let window, let backdrop = subviews.first?.layer else { return }
        backdrop.setValue(window.screen.scale, forKey: "scale")
    }

    private func applyVariableBlur() {
        guard
            let backdrop = subviews.first?.layer,
            let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
            let filter = filterClass
                .perform(NSSelectorFromString("filterWithType:"), with: "variableBlur")?
                .takeUnretainedValue() as? NSObject,
            let mask = Self.gradientMask
        else { return }
        filter.setValue(maxRadius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        // Renormalize the kernel where it hangs past the layer's edges, so the
        // top rows of pixels don't darken toward the sampled void.
        filter.setValue(true, forKey: "inputNormalizeEdges")
        backdrop.filters = [filter]
    }

    /// The vertical alpha ramp steering the radius: fully opaque (full blur)
    /// through the top half, easing to clear (no blur) at the bottom — the same
    /// solid-then-fade profile the material bands drew with their masks. The
    /// mask stretches to the layer, so 1×100 carries the whole profile.
    private static let gradientMask: CGImage? = {
        let size = CGSize(width: 1, height: 100)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.cgColor,
                    UIColor.white.cgColor,
                    UIColor.white.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
        return image.cgImage
    }()
}
