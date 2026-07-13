import Foundation

/// The launch-time offer to seed the input with what the user just copied
/// (CONTEXT.md → Clipboard prefill; ADR 0002 — no automatic clipboard history).
///
/// This is the platform-agnostic *decision*, not the pasteboard plumbing. iOS
/// reading a clipboard's content fires the system "pasted from…" banner, so the
/// whole privacy posture rests on one rule: whether to *offer* the chip is
/// decided from metadata alone — the silent `hasStrings` check — never from the
/// content itself. The App feeds this value `UIPasteboard.general.hasStrings`
/// and the current input state; the content is read only when the user taps the
/// system Paste control, well after this decision is made.
public struct ClipboardPrefill: Equatable, Sendable {
    /// Whether the tap-to-fill paste chip should be shown right now.
    public let isChipOffered: Bool

    /// Decides whether to offer the chip from the app-level setting, launch-time
    /// metadata (`clipboardHasText`, i.e. `UIPasteboard.hasStrings`), the input
    /// state, and whether the offer has already been taken this launch. No
    /// clipboard *content* enters this initializer by design.
    ///
    /// - Parameter isEnabled: the app-level **Clipboard prefill** toggle
    ///   (CONTEXT.md → Settings; issue #65), default on. Off suppresses the chip
    ///   outright — the setting gates the *offer*; the silent metadata check is
    ///   banner-free either way.
    /// - Parameter hasBeenUsed: whether the chip has already seeded the input
    ///   since the app started. The offer is once-per-launch: once taken it stays
    ///   gone until the next app start, even though the clipboard still holds text
    ///   and the user may return to Home by clearing the input.
    public init(isEnabled: Bool = true, clipboardHasText: Bool, isHome: Bool, hasBeenUsed: Bool = false) {
        // The chip is a Home affordance: offered only when the setting allows it,
        // only in the empty-query state, and only when the metadata check found
        // text. The first keystroke (isHome == false) withdraws it as Results
        // takes over; taking the offer (hasBeenUsed) retires it for the rest of
        // the launch.
        self.isChipOffered = isEnabled && clipboardHasText && isHome && !hasBeenUsed
    }

    /// The hand-off decision for a tapped paste: the query the pasted content
    /// should seed — edge-trimmed of copy artifacts like a dragged-along trailing
    /// newline, interior whitespace intact — or `nil` when the paste turned out
    /// to be a dud (empty or whitespace-only, i.e. nothing visible to seed).
    ///
    /// The offer above is decided from metadata alone, and `hasStrings` is blind
    /// to *what* the string is — an app that "clears" the clipboard by writing
    /// an empty string still reports text present, so the chip can be offered
    /// with nothing usable behind it. The content itself arrives only with the
    /// user's tap, which makes this the first moment the dud can be detected.
    /// On a dud the host should withdraw the chip (the metadata was wrong)
    /// *without* burning the once-per-launch offer — see
    /// `ClipboardPrefillModel.noteEmptyPaste()` — so a later real copy can
    /// re-offer it.
    public static func seededQuery(fromPasted text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
