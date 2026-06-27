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

    /// Decides whether to offer the chip from launch-time metadata
    /// (`clipboardHasText`, i.e. `UIPasteboard.hasStrings`), the input state, and
    /// whether the offer has already been taken this launch. No clipboard
    /// *content* enters this initializer by design.
    ///
    /// - Parameter hasBeenUsed: whether the chip has already seeded the input
    ///   since the app started. The offer is once-per-launch: once taken it stays
    ///   gone until the next app start, even though the clipboard still holds text
    ///   and the user may return to Home by clearing the input.
    public init(clipboardHasText: Bool, isHome: Bool, hasBeenUsed: Bool = false) {
        // The chip is a Home affordance: offered only in the empty-query state and
        // only when the metadata check found text. The first keystroke (isHome ==
        // false) withdraws it as Results takes over; taking the offer
        // (hasBeenUsed) retires it for the rest of the launch.
        self.isChipOffered = clipboardHasText && isHome && !hasBeenUsed
    }
}
