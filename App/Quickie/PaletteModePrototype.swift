import SwiftUI
import GameController
import QuickieCore

// ─────────────────────────────────────────────────────────────────────────────
// PROTOTYPE — THROWAWAY. Not for merge. Issue #269, branch
// `prototype/ipad-palette-mode`. Everything in this file, and every `#if` /
// `PalettePrototype.` reference elsewhere in the App target, exists to answer one
// design question and is deleted with the branch.
//
// The question (iPad UI audit §5, direction alternative B): on a regular-width
// window with a hardware keyboard attached — so no software keyboard eats the
// bottom half of the screen — should the launcher flip from its bottom-docked
// column to a Spotlight/Raycast palette: input in the top third, results
// dropping downward?
//
// What the prototype has to prove or kill:
//   1. rank-0 adjacency — rank 0 must still sit directly against the input
//      (ADR 0008's guarantee), just below it instead of above it.
//   2. the motion budget for the flip (ADR 0010) — what does the mode change
//      actually cost, and can it stay inside the budget?
//   3. whether mode-flipping disorients — the launcher rearranging itself
//      because a keyboard was attached or detached.
//
// Unreachable without `-palette-prototype`, so a build of this branch is the
// shipping launcher until you ask for the prototype.
// ─────────────────────────────────────────────────────────────────────────────
enum PalettePrototype {
    /// Which way the launcher is laid out.
    enum Mode: Equatable {
        /// Today's shipping layout: input docked at the bottom, results reversed
        /// and stacking upward off it (ADR 0008).
        case docked
        /// Alternative B: input in the top third, results dropping downward.
        case palette
    }

    private static let arguments = ProcessInfo.processInfo.arguments

    /// The whole prototype seam. Off ⇒ the launcher is byte-for-byte today's.
    static let isEnabled = arguments.contains("-palette-prototype")

    /// Pins the mode regardless of the real trigger, so the two layouts can be
    /// captured side by side from a script without physically attaching and
    /// detaching a keyboard between shots: `-palette-mode docked|palette`.
    static let pinnedMode: Mode? = {
        guard let i = arguments.firstIndex(of: "-palette-mode"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "docked": return .docked
        case "palette": return .palette
        default: return nil
        }
    }()

    /// Draws the trigger inputs and the resolved mode in the corner, so a
    /// screenshot says *why* it is laid out the way it is.
    static let showsBadge = arguments.contains("-palette-badge")

    /// A hidden `⌘⇧P` that flips the mode by hand, so the *flip itself* can be
    /// driven from a script and filmed frame by frame. The real trigger is a
    /// keyboard being attached or detached, which is not something a test can do
    /// to itself — but the transition it causes is what the motion budget
    /// question is about, so it needs a deterministic handle.
    static let allowsManualFlip = arguments.contains("-palette-manual-flip")

    /// Forces the *hardware keyboard attached* term true, and nothing else.
    ///
    /// Deliberately narrower than `-palette-mode`: that pins the whole answer,
    /// this supplies only the one input a simulator cannot produce, leaving the
    /// size class, the software-keyboard term and the decision itself to run for
    /// real. `GCKeyboard.coalesced` stays nil in the simulator even with Connect
    /// Hardware Keyboard on — the passthrough is not a Game Controller keyboard —
    /// so without this the trigger path cannot be exercised off-device at all.
    static let forcesHardwareKeyboard = arguments.contains("-palette-force-hardware-keyboard")

    /// `-palette-auto-flip <seconds>`: the launcher flips modes by itself on that
    /// interval, forever.
    ///
    /// Three ways of causing the flip were tried before this one, and each failed
    /// *silently* — a run of identical frames that looked like a transition too
    /// fast to catch. A `⌘⇧P` on a zero-size hidden button was never installed as
    /// a shortcut at all, and pressing the key made XCUITest raise the software
    /// keyboard, so the diff measured a keyboard rather than a mode. Moving to a
    /// tap target put it under the palette's own top safe-area inset, which
    /// swallowed it. A timer has no hit-testing and no key events to get wrong: it
    /// is the only handle here that cannot be intercepted by the layout it exists
    /// to change.
    static let autoFlipInterval: Double? = {
        guard let i = arguments.firstIndex(of: "-palette-auto-flip"), i + 1 < arguments.count,
              let seconds = Double(arguments[i + 1]), seconds > 0 else { return nil }
        return seconds
    }()

    /// Seeds the query at launch, so a state can be captured with a plain
    /// `simctl launch` rather than an XCUITest that has to *type* it.
    ///
    /// This matters more than it looks. XCUITest raises the **software** keyboard
    /// in order to type, which is exactly the condition palette mode is defined by
    /// the absence of — so a driver that types can never photograph the mode it is
    /// trying to photograph.
    static let seededQuery: String? = {
        guard let i = arguments.firstIndex(of: "-palette-seed-query"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }()

    /// **The trigger.** Palette mode is earned by two conditions at once:
    ///
    /// - **regular width** — the same size-class switch the readable command
    ///   column already turns on (ADR 0039), never the device idiom, so an iPad
    ///   dragged into Split View comes back to the docked layout.
    /// - **a hardware keyboard attached, and no software keyboard on screen** —
    ///   the actual argument for the flip. The bottom dock is a thumb-reach
    ///   decision; with a hardware keyboard there is no thumb and nothing under
    ///   the bar, so it floats alone at the foot of a big empty canvas and the
    ///   eye-line argument takes over.
    ///
    /// **The first version of this got the keyboard condition wrong, and how it
    /// was wrong is one of the prototype's findings.** It read
    /// `KeyboardBarLift.Geometry.isSoftwareKeyboard` — the keyboard's own height,
    /// off the `keyboardWillChangeFrame` the bar lift already consumes. That
    /// answers *"was the keyboard that just announced itself a software one?"*,
    /// which is the right question for a lift and the wrong one here: with a
    /// hardware keyboard attached, iPadOS 26 posts **no keyboard notification at
    /// all** — there is no accessory bar to announce. So the state never left its
    /// initial value, and the launcher stayed docked on exactly the device the
    /// mode exists for. **The absence of a keyboard is not a keyboard event.**
    ///
    /// A hardware keyboard's *presence* has its own API — `GCKeyboard.coalesced`,
    /// with connect and disconnect notifications — and that is what a layout
    /// decision has to read. The software-keyboard term stays as the second half,
    /// because a hardware keyboard does not stop iPadOS putting a floating or
    /// split keyboard on screen, and while one is up the bottom is occupied again.
    static func mode(
        sizeClass: CommandColumn.SizeClass,
        hasHardwareKeyboard: Bool,
        hasSoftwareKeyboard: Bool
    ) -> Mode {
        if let pinnedMode { return pinnedMode }
        return sizeClass == .regular && hasHardwareKeyboard && !hasSoftwareKeyboard ? .palette : .docked
    }

    /// How far down the window the palette's input sits, as a fraction of the
    /// window's height — the "top third" of the audit's mock, measured to the
    /// *top* of the input so the field's centre lands near 0.22.
    ///
    /// Not centred and not fixed: a fraction keeps the field on roughly the same
    /// eye-line whether the window is a 13" iPad or a half-height Stage Manager
    /// tile, which is the entire ergonomic claim being tested.
    static let inputTopFraction: CGFloat = 0.18
}

/// Whether a hardware keyboard is attached, as a live signal.
///
/// `GCKeyboard.coalesced` is the only thing that answers this: non-nil while any
/// hardware keyboard is connected, with Game Controller notifications for the
/// transitions. Nothing in the keyboard *frame* notifications can stand in for it
/// — see `PalettePrototype.mode`.
@Observable
@MainActor
final class HardwareKeyboardMonitor {
    private(set) var isAttached = PalettePrototype.forcesHardwareKeyboard || GCKeyboard.coalesced != nil

    /// Observers are never removed: the monitor lives as long as the launcher
    /// does, which is as long as the process. Throwaway code — a real version
    /// would hold them and tear down.
    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isAttached = PalettePrototype.forcesHardwareKeyboard || GCKeyboard.coalesced != nil
                }
            }
        }
    }

}

/// The corner read-out (`-palette-badge`): the trigger's inputs and its answer.
struct PalettePrototypeBadge: View {
    let sizeClass: CommandColumn.SizeClass
    let hasHardwareKeyboard: Bool
    let hasSoftwareKeyboard: Bool
    let mode: PalettePrototype.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mode == .palette ? "PALETTE" : "DOCKED").bold()
            Text("width:    \(sizeClass == .regular ? "regular" : "compact")")
            Text("hardware: \(hasHardwareKeyboard ? "attached" : "none")")
            Text("software: \(hasSoftwareKeyboard ? "on screen" : "none")")
            if PalettePrototype.pinnedMode != nil { Text("(pinned)") }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
        .accessibilityIdentifier("palette-prototype-badge")
        .allowsHitTesting(false)
    }
}
