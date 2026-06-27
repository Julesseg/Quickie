import SwiftUI

/// The tap-to-fill paste chip offered on Home when the clipboard holds text
/// (CONTEXT.md → Clipboard prefill; ADR 0002). It is backed by the system paste
/// control — SwiftUI's `PasteButton`, the front-end to `UIPasteControl` — which
/// reads the clipboard *only* when tapped and never raises the "pasted from…"
/// banner. Nothing here touches `UIPasteboard.string`; the content arrives only
/// through the user's tap, then seeds the input and the chip gives way to the
/// normal Result list (the seeded, non-empty query leaves the Home state).
struct ClipboardPasteChip: View {
    @Binding var query: String

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            // Reached only on an explicit tap of the system paste control, so
            // this is the first and only moment any content is read.
            guard let text = strings.first else { return }
            query = text
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("clipboard-paste-chip")
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
