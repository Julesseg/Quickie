import Foundation
#if canImport(CoreGraphics)
// Darwin puts CGRect's geometry accessors (minX, maxY, width …) in CoreGraphics;
// swift-corelibs-foundation defines them inside Foundation itself, so the Linux
// `swift test` run needs no import at all.
import CoreGraphics
#endif

/// The bottom bar's keyboard lift as a pure decision (issues #58 × #64, extended
/// to windowed geometry by #261). The bar is lifted manually — SwiftUI's
/// automatic avoidance is off — and must track the keyboard *exactly*: riding
/// the keyboard's own show/hide animation instead of settling after it, and
/// following the finger during an interactive swipe-dismiss, while still
/// **holding** its inset when a context menu transiently resigns first responder.
///
/// Two input channels feed it, and the split is what tells the cases apart:
/// - `notified` — a `keyboardWillChangeFrame` end-frame. Fires at animation
///   start, so its change is applied *animated with the keyboard's timing*.
/// - `dragged` — a live keyboard-frame sample (the App's keyboard layout guide)
///   while a list drag is interactively moving the keyboard. Applied
///   immediately, unanimated: the finger is the animation.
///
/// All geometry here is in the **window's** coordinate space, never the
/// screen's: on iPad the app's window is only sometimes the display (Split View,
/// Slide Over, Stage Manager, iPadOS 26 free resizing), so screen-space math
/// lifts the bar by an amount that has nothing to do with what the keyboard
/// actually covers. The App converts the notification's end-frame with
/// `UIWindow.convert(_:from:)` before calling in (ADR 0040).
public enum KeyboardBarLift {
    /// The height separating a real software keyboard from a hardware keyboard's
    /// thin shortcuts bar. Compared against the keyboard's **own** height — see
    /// `Geometry.isSoftwareKeyboard`.
    public static let softwareKeyboardThreshold: CGFloat = 120

    /// How far a keyboard edge may fall short of a window edge and still count
    /// as meeting it — absorbs the sub-point rounding of a converted frame.
    private static let edgeTolerance: CGFloat = 1

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

    /// How a keyboard end-frame relates to the window it must not cover. Naming
    /// the three cases once keeps the lift rules below reading as policy rather
    /// than as rect arithmetic.
    public enum Coverage: Equatable, Sendable {
        /// Docked against the window's bottom edge — as wide as the window and
        /// running to (or past) its bottom — covering `overlap` points of it.
        /// `overlap` is zero when the keyboard has dropped clean below the
        /// window: a dismissal, or a window floating above a keyboard that
        /// belongs to the display, not to it.
        case docked(overlap: CGFloat)
        /// A floating or split keyboard: inside the window but detached from its
        /// bottom edge, so it covers no band the bar has to clear.
        case undocked
        /// No keyboard to speak of — an empty frame, or one clean outside the
        /// window.
        case away
    }

    /// Where the keyboard is relative to the window it must not cover, all in
    /// the window's own coordinate space — the only space in which "how much of
    /// the bar does the keyboard cover?" has an answer (ADR 0040). The App
    /// converts the notification's screen-space end-frame and reads the bounds
    /// and inset off the same window at the same moment, so the three can never
    /// disagree about which window they describe.
    public struct Geometry: Equatable, Sendable {
        /// The keyboard's end-frame. May sit partly or wholly outside the
        /// window — that is exactly what `coverage` reads.
        public var keyboardFrame: CGRect
        /// The host window's bounds.
        public var windowBounds: CGRect
        /// The host window's bottom safe-area inset: the band the bar already
        /// sits in, and so the part of any coverage it need not clear.
        public var bottomSafeArea: CGFloat

        public init(keyboardFrame: CGRect, windowBounds: CGRect, bottomSafeArea: CGFloat) {
            self.keyboardFrame = keyboardFrame
            self.windowBounds = windowBounds
            self.bottomSafeArea = bottomSafeArea
        }

        /// Docked means the keyboard is **as wide as the window** and reaches
        /// its bottom edge — true at full screen, in Split View and Slide Over
        /// (where a display-wide keyboard overhangs a narrow window on both
        /// sides), and for a Stage Manager window whose bottom sits over the
        /// keyboard. Width rather than edge-to-edge coverage, because under
        /// iPadOS 26 free placement a window can hang off a display edge: the
        /// display-wide keyboard still covers every visible point of its bottom
        /// band without ever reaching the window's off-screen edge.
        ///
        /// Anything else that still falls inside the window is a floating or
        /// split keyboard, which leaves the window's bottom edge free.
        public var coverage: Coverage {
            guard keyboardFrame.width > 0, keyboardFrame.height > 0 else { return .away }

            let spansWindowWidth = keyboardFrame.width >= windowBounds.width - edgeTolerance
                && keyboardFrame.minX < windowBounds.maxX
                && keyboardFrame.maxX > windowBounds.minX
            let reachesWindowBottom = keyboardFrame.maxY >= windowBounds.maxY - edgeTolerance
            if spansWindowWidth, reachesWindowBottom {
                let coveredTop = max(keyboardFrame.minY, windowBounds.minY)
                return .docked(overlap: max(0, windowBounds.maxY - coveredTop))
            }

            return keyboardFrame.intersects(windowBounds) ? .undocked : .away
        }

        /// Whether this is a real software keyboard rather than a hardware
        /// keyboard's shortcuts bar. Read from the keyboard's **own** height,
        /// never its window overlap: a window shorter than the keyboard (Stage
        /// Manager) sees only a sliver of it, and classifying on that clipped
        /// value would read a full keyboard as an accessory bar.
        public var isSoftwareKeyboard: Bool {
            keyboardFrame.height > softwareKeyboardThreshold
        }

        /// The bar's inset for a given coverage of the window's bottom: what is
        /// covered, less the safe area the bar already sits in.
        func inset(clearing overlap: CGFloat) -> CGFloat {
            max(0, overlap - bottomSafeArea)
        }
    }

    /// Decide from a `keyboardWillChangeFrame` end-frame, resolved against the
    /// window it arrived in.
    ///
    /// `isLocalKeyboard` is the notification's own `keyboardIsLocalUserInfoKey`:
    /// side by side on iPad, the *other* app's keyboard posts here too, and
    /// though it may well cover our window, nothing of ours is focused — so it
    /// must leave our bar exactly where it is.
    public static func notified(
        _ geometry: Geometry,
        isLocalKeyboard: Bool,
        isListScrolling: Bool,
        usesKeyboardlessControl: Bool
    ) -> Change {
        guard isLocalKeyboard else { return .hold }

        switch geometry.coverage {
        case .docked(let overlap) where overlap > 0:
            // A docked keyboard of any height — a software keyboard or a hardware
            // keyboard's shortcuts bar — lifts the bar by exactly what it covers,
            // so the accessory bar gets the accessory bar's lift and can never
            // leave a full keyboard's inset stranded beneath it.
            return .animateWithKeyboard(inset: geometry.inset(clearing: overlap))

        case .undocked:
            // A floating or split keyboard covers nothing at the window's bottom:
            // the bar rests there. Released rather than held, so undocking a
            // keyboard that *had* lifted the bar drops it back down.
            return .animateWithKeyboard(inset: 0)

        case .docked, .away:
            // Nothing covers the window's bottom edge. *Which* way the keyboard
            // left decides whether the held inset survives:
            //  • **while the list is being dragged**: an intentional
            //    swipe-dismiss (issue #64) — release, so more results show.
            //  • **into a keyboard-less capture control** (the date step's
            //    picker, the primer/denial affordances): the text field was
            //    removed for the whole step, so the keyboard is structurally
            //    gone — release, and let the control take its space.
            //  • **a software keyboard, list still**: a context menu resigned
            //    first responder (issue #58) — **hold**, so the long-press never
            //    reflows the list. This is the whole point of driving the lift
            //    ourselves.
            //  • **a hardware keyboard's accessory bar, list still**: there is no
            //    software keyboard whose inset is worth preserving, so release
            //    rather than freeze the bar above a dead band.
            if isListScrolling || usesKeyboardlessControl {
                return .animateWithKeyboard(inset: 0)
            }
            return geometry.isSoftwareKeyboard ? .hold : .animateWithKeyboard(inset: 0)
        }
    }

    /// Decide at the moment a capture's current step changes. Entering a
    /// keyboard-less step (the date picker) removes the text field, so the
    /// keyboard is structurally gone — release the inset *immediately*,
    /// unanimated, rather than waiting for the keyboard-hide notification: the
    /// step's control then lays out in its final position behind the dismissing
    /// keyboard instead of appearing keyboard-high and sliding down with it.
    public static func stepChanged(usesKeyboardlessControl: Bool) -> Change {
        usesKeyboardlessControl ? .track(inset: 0) : .hold
    }

    /// Decide from a live keyboard-frame sample (the App's keyboard layout
    /// guide, whose overlap is always measured against the window it lives in).
    ///
    /// The notified channel owns ordinary show/hide, so a live sample only acts
    /// when it carries something that channel cannot have:
    /// - **a list drag in flight** — the interactive swipe-dismiss moving the
    ///   keyboard under the finger (issue #64), where
    ///   `keyboardWillChangeFrame` fires only once the gesture commits;
    /// - **the window changing shape** under a keyboard that has not moved — a
    ///   Split View divider drag, a Stage Manager or iPadOS 26 resize, a
    ///   rotation. The keyboard's own frame is unchanged, so it posts nothing at
    ///   all; without this the bar would keep the inset it had at the window's
    ///   *old* size (issue #261).
    ///
    /// Both are the user's finger on something, so both are applied
    /// immediately, unanimated: the finger is the animation. Every other sample
    /// is the keyboard's own animation playing out (or a context-menu
    /// resignation) and is ignored, so it can never fight the notified channel
    /// or a held inset.
    ///
    /// The guide does not follow an undocked keyboard (`followsUndockedKeyboard`
    /// stays off), so a floating or split keyboard reports zero overlap here —
    /// the same answer `Geometry.coverage` gives it.
    public static func live(
        overlap: CGFloat,
        bottomSafeArea: CGFloat,
        isListScrolling: Bool,
        windowChangedShape: Bool
    ) -> Change {
        guard isListScrolling || windowChangedShape else { return .hold }
        return .track(inset: max(0, overlap - bottomSafeArea))
    }
}
