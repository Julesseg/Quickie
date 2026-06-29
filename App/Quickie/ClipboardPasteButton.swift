import SwiftUI
import UIKit

/// The icon-only paste control offered to the *right of the input* on Home when
/// the clipboard holds text (CONTEXT.md → Clipboard prefill; ADR 0002). It is
/// backed by the system paste control — `UIPasteControl`, the front-end SwiftUI's
/// `PasteButton` also wraps — which reads the clipboard *only* when tapped and
/// never raises the "pasted from…" banner. Nothing here touches
/// `UIPasteboard.string`; the content arrives only through the user's tap, then
/// seeds the input and the button retires for the session (the seeded, non-empty
/// query leaves Home).
///
/// We drop down to `UIPasteControl` directly (rather than SwiftUI's `PasteButton`)
/// for one reason: SwiftUI exposes no way to clear `PasteButton`'s own fill —
/// `.tint(.clear)` only repaints it the label colour, leaving an opaque rectangle
/// inside our glass. `UIPasteControl.Configuration.baseBackgroundColor = .clear`
/// removes it entirely, so the only surface is our own `glassEffect`. That single
/// glass shape, paired by `glassEffectID` with the input's (`InputBar.glassID`)
/// inside the bottom `GlassEffectContainer`, is what lets the button *morph out of
/// and back into* the input's capsule as it is offered and withdrawn.
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
            .glassEffect(.regular.interactive(), in: Circle())
            .glassEffectID(Self.glassID, in: glassNamespace)
    }
}

/// A thin wrapper over `UIPasteControl`, configured with a clear background and an
/// icon-only display so the only visible surface is the host's Liquid Glass. The
/// control still does the privacy-preserving work: it reads the pasteboard only on
/// the user's tap (no "pasted from…" banner), then hands the text up the responder
/// chain to `PasteReceiverView.paste(itemProviders:)`.
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
        // The whole point: clear the control's own fill so our glass is the surface.
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule

        let control = UIPasteControl(configuration: configuration)
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
