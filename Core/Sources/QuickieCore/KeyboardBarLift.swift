import Foundation

/// The bottom bar's keyboard lift as a pure decision (issues #58 × #64). The bar
/// is lifted manually — SwiftUI's automatic avoidance is off — and must track the
/// keyboard *exactly*: riding the keyboard's own show/hide animation instead of
/// settling after it, and following the finger during an interactive
/// swipe-dismiss, while still **holding** its inset when a context menu
/// transiently resigns first responder.
///
/// Two input channels feed it, and the split is what tells the cases apart:
/// - `notified` — a `keyboardWillChangeFrame` end-frame. Fires at animation
///   start, so its change is applied *animated with the keyboard's timing*.
/// - `dragged` — a live keyboard-frame sample (the App's keyboard layout guide)
///   while a list drag is interactively moving the keyboard. Applied
///   immediately, unanimated: the finger is the animation.
public enum KeyboardBarLift {
    /// The threshold separating a real software keyboard from a hardware
    /// keyboard's thin accessory bar: overlaps at or below it never lift the bar.
    public static let softwareKeyboardThreshold: CGFloat = 120

    public enum Change: Equatable, Sendable {
        /// Move the bar to `inset`, animated in step with the keyboard's own
        /// show/hide animation.
        case animateWithKeyboard(inset: CGFloat)
        /// Move the bar to `inset` immediately, unanimated — a live drag sample
        /// where the finger is the animation.
        case track(inset: CGFloat)
        /// Keep the held inset untouched — the transient context-menu dismissal,
        /// or a live sample that isn't a drag.
        case hold
    }

    /// Whether a `keyboardWillChangeFrame` end-frame puts a real software
    /// keyboard on screen. Beyond the bar lift, this is the visibility signal
    /// the return-trip refocus guards on: a keyboard that is already up must
    /// never be toggled down just to re-raise it — the return-from-a-page
    /// flicker (keyboard up during the pop, yanked at completion, slid back up).
    public static func showsSoftwareKeyboard(overlap: CGFloat) -> Bool {
        overlap > softwareKeyboardThreshold
    }

    /// Decide from a `keyboardWillChangeFrame` end-frame. `overlap` is the
    /// keyboard's coverage of the screen bottom; the bar already sits in the
    /// bottom safe area, so the lift is the overlap beyond it.
    public static func notified(
        overlap: CGFloat,
        bottomSafeArea: CGFloat,
        isListScrolling: Bool,
        usesKeyboardlessControl: Bool
    ) -> Change {
        if showsSoftwareKeyboard(overlap: overlap) {
            return .animateWithKeyboard(inset: max(0, overlap - bottomSafeArea))
        }
        if isListScrolling || usesKeyboardlessControl {
            return .animateWithKeyboard(inset: 0)
        }
        return .hold
    }

    /// Decide from a live keyboard-frame sample (the App's keyboard layout
    /// guide). Only a sample taken *while a list drag is in flight* is the
    /// interactive swipe-dismiss moving the keyboard under the finger — track it
    /// exactly. Samples while still are the keyboard's own animation (or a
    /// context-menu resignation) and are ignored: the notified channel owns those.
    public static func dragged(
        overlap: CGFloat,
        bottomSafeArea: CGFloat,
        isListScrolling: Bool
    ) -> Change {
        guard isListScrolling else { return .hold }
        return .track(inset: max(0, overlap - bottomSafeArea))
    }
}
