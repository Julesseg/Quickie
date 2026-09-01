import SwiftUI
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

    /// **The trigger.** Palette mode is earned by two conditions at once, and
    /// both matter:
    ///
    /// - **regular width** — the same size-class switch the readable command
    ///   column already turns on (ADR 0039), never the device idiom, so an iPad
    ///   dragged into Split View comes back to the docked layout.
    /// - **no software keyboard** — the actual argument for the flip. The
    ///   bottom dock is a thumb-reach decision; with a hardware keyboard there
    ///   is no thumb and no keyboard under the bar, so the bar floats alone at
    ///   the foot of a big empty canvas and the eye-line argument takes over.
    ///
    /// `hasSoftwareKeyboard` comes from `KeyboardBarLift.Geometry.isSoftwareKeyboard`
    /// — the keyboard's **own** height, not its overlap of the window (ADR 0040),
    /// which is what keeps a dismissed software keyboard (reported at full height,
    /// off-screen below) from reading as a hardware one and flipping the layout on
    /// every dismissal.
    static func mode(sizeClass: CommandColumn.SizeClass, hasSoftwareKeyboard: Bool) -> Mode {
        if let pinnedMode { return pinnedMode }
        return sizeClass == .regular && !hasSoftwareKeyboard ? .palette : .docked
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

/// The corner read-out (`-palette-badge`): the trigger's inputs and its answer.
struct PalettePrototypeBadge: View {
    let sizeClass: CommandColumn.SizeClass
    let hasSoftwareKeyboard: Bool
    let mode: PalettePrototype.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mode == .palette ? "PALETTE" : "DOCKED").bold()
            Text("width: \(sizeClass == .regular ? "regular" : "compact")")
            Text("keyboard: \(hasSoftwareKeyboard ? "software" : "hardware")")
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
