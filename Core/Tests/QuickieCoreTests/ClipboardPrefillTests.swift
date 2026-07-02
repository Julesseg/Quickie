import Foundation
import Testing
@testable import QuickieCore

// Clipboard prefill is the launch-time, banner-free offer to seed the input with
// what the user just copied (CONTEXT.md → Clipboard prefill; ADR 0002). The whole
// privacy posture rests on one rule: whether to *offer* the chip is decided from
// metadata alone — the silent `hasStrings` check — and the actual content is read
// only when the user taps the system Paste control. `ClipboardPrefill` is the
// platform-agnostic decision; the App feeds it `UIPasteboard.hasStrings` and the
// current input state, then renders (or hides) the chip accordingly.
struct ClipboardPrefillTests {

    @Test("offers the paste chip when the clipboard has text at launch")
    func offersChipWhenClipboardHasText() {
        let prefill = ClipboardPrefill(clipboardHasText: true, isHome: true)
        #expect(prefill.isChipOffered)
    }

    @Test("withholds the chip when the clipboard has no text")
    func noChipWhenClipboardEmpty() {
        let prefill = ClipboardPrefill(clipboardHasText: false, isHome: true)
        #expect(prefill.isChipOffered == false)
    }

    @Test("withdraws the chip once the user starts typing (Home → Results)")
    func noChipOnceTyping() {
        // The chip is a Home affordance; the first keystroke hands the screen to
        // the Result list, so the offer is gone even though the clipboard still
        // has text.
        let prefill = ClipboardPrefill(clipboardHasText: true, isHome: false)
        #expect(prefill.isChipOffered == false)
    }

    @Test("a used chip stays gone for the session, even back on Home with text")
    func noChipAfterUseThisSession() {
        // The offer is a once-per-launch thing: after the user has taken it, the
        // clipboard still holds text and clearing the input returns to Home — but
        // the chip must not come back until the next app start.
        let prefill = ClipboardPrefill(clipboardHasText: true, isHome: true, hasBeenUsed: true)
        #expect(prefill.isChipOffered == false)
    }

    @Test("the Clipboard prefill setting off suppresses the chip entirely")
    func noChipWhenSettingOff() {
        // The app-level **Clipboard prefill** toggle (CONTEXT.md → Settings;
        // issue #65): off means the chip never appears, even in the exact state
        // that would otherwise offer it (text on the clipboard, on Home, unused).
        let prefill = ClipboardPrefill(isEnabled: false, clipboardHasText: true, isHome: true)
        #expect(prefill.isChipOffered == false)
    }
}
