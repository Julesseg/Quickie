import SwiftUI
import UIKit

/// The icon-only paste control offered to the *right of the input* on Home when
/// the clipboard holds text (CONTEXT.md → Clipboard prefill; ADR 0002). It is
/// backed by the system paste control — `UIPasteControl`, the front-end SwiftUI's
/// `PasteButton` also wraps — which reads the clipboard *only* when tapped:
/// nothing here touches `UIPasteboard.string`, the content arrives only through
/// the user's tap, then seeds the input and the button retires for the session
/// (the seeded, non-empty query leaves Home).
///
/// **Do not describe this chip as prompt-free or banner-free.** The bare system
/// paste control is exempt from the iOS paste-permission alert, but *only while
/// shown untouched*; dressing it in the input bar's Liquid Glass (below) forfeits
/// that exemption, so tapping the chip **does** raise the alert. That is a
/// deliberate, accepted trade-off — the glass look over the exemption — recorded
/// in the glossary (CONTEXT.md → Clipboard prefill), not a bug to "fix" by
/// stripping the dressing; the mitigation is the [[Paste permission hint]] in
/// Settings, which tells the user how to silence the alert for good. Only the
/// launch-time *has-text* metadata check (`UIPasteboard.hasStrings`) is silent.
///
/// Neither SwiftUI's `PasteButton` nor `UIPasteControl` lets us clear its own
/// opaque platter — `.tint(.clear)` / `baseBackgroundColor = .clear` are ignored
/// and it renders a solid (black) disc, which clashed with the input's translucent
/// glass. So the system control is kept as the (invisible) tap target — its alpha
/// dropped just above UIKit's hit-test floor so taps still register and paste — and
/// we draw our own icon over our own `glassEffect`. That single glass shape, paired
/// by `glassEffectID` with the input's (`InputBar.glassID`) inside the bottom
/// `GlassEffectContainer`, is what lets the button *morph out of and back into* the
/// input's capsule as it is offered and withdrawn — and, per the trade-off above,
/// is exactly what costs the bare control its paste-permission-alert exemption.
///
/// It is a fixed circle of `InputBar.barHeight` — exactly the input's height — so
/// the two read as one consistent body and the row never changes height as the
/// button comes and goes.
struct ClipboardPasteButton: View {
    /// Stable identity for this button's Liquid Glass within the bottom
    /// `GlassEffectContainer`, paired with `InputBar.glassID` to drive the morph.
    static let glassID = "clipboard-paste"

    /// The shared namespace the bottom glass surfaces morph within — pairs this
    /// button's glass with the input's so SwiftUI interpolates one into the other.
    var glassNamespace: Namespace.ID

    /// Delivers the pasted text to the host on tap. The host seeds the input and
    /// retires the button for the session — the button itself stays content-unaware
    /// beyond this single hand-off.
    let onPaste: (String) -> Void

    var body: some View {
        SystemPasteControl(onPaste: onPaste)
            .frame(width: InputBar.barHeight, height: InputBar.barHeight)
            // Our icon, over the glass — the invisible control beneath takes the tap.
            // `allowsHitTesting(false)` lets the tap fall through to that control.
            .overlay {
                Image(systemName: "doc.on.clipboard")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .glassEffect(.regular.interactive(), in: Circle())
            .glassEffectID(Self.glassID, in: glassNamespace)
    }
}

/// A thin wrapper over `UIPasteControl`, kept as an invisible tap target beneath
/// the host's own icon and Liquid Glass (its platter can't be made transparent, so
/// we hide it rather than show it). The control still does the privacy-preserving
/// work: it reads the pasteboard only on the user's tap, then delivers the text to
/// its `target`, `PasteReceiverView.paste(itemProviders:)`. Hiding the bare control
/// behind our own glass is exactly what forfeits its exemption from the iOS
/// paste-permission alert — a deliberate, accepted trade-off (CONTEXT.md →
/// Clipboard prefill, Paste permission hint), so the tap is *not* prompt-free.
private struct SystemPasteControl: UIViewRepresentable {
    let onPaste: (String) -> Void

    func makeUIView(context: Context) -> PasteReceiverView {
        let host = PasteReceiverView()
        host.onPaste = onPaste
        // Declaring what the host accepts is what enables the control (and lets it
        // report it can paste) when the pasteboard holds matching content.
        host.pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)

        var configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .capsule

        let control = UIPasteControl(configuration: configuration)
        // The control's platter can't be cleared, so hide the whole control and let
        // our own icon/glass show instead. 0.02 is just above UIKit's hit-test alpha
        // floor (0.01), so the control is invisible yet still receives the tap.
        control.alpha = 0.02
        // Without an explicit target the paste action is sent to the *first
        // responder* — the search field, here — so it never reaches us and nothing
        // pastes. Point it at the host so `paste(itemProviders:)` below is called.
        control.target = host
        control.translatesAutoresizingMaskIntoConstraints = false
        // The XCUITest (`ClipboardPrefillUITests`) and the chip's contract address
        // it by this identifier; keep it on the control itself, which is the button.
        control.accessibilityIdentifier = "clipboard-paste-chip"
        host.addSubview(control)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: host.topAnchor),
            control.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            control.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        return host
    }

    func updateUIView(_ uiView: PasteReceiverView, context: Context) {
        uiView.onPaste = onPaste
    }
}

/// The responder that receives the pasted content. It is set as the control's
/// explicit `target` (see `makeUIView`), so on tap UIKit calls `paste(itemProviders:)`
/// here directly — bypassing the first responder (the search field) that would
/// otherwise swallow the action — and we hand the text back to the host closure.
final class PasteReceiverView: UIView {
    var onPaste: ((String) -> Void)?

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) })
        else { return }
        // Reached only on an explicit tap of the system paste control, so this is
        // the first and only moment any content is read.
        provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let text = object as? String else { return }
            DispatchQueue.main.async { self?.onPaste?(text) }
        }
    }
}
