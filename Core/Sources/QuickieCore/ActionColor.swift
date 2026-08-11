import Foundation

/// Which appearance a palette swatch is being resolved for (CONTEXT.md → Action
/// color; issue #243). The palette is tuned per scheme in Core — a token means
/// "this hue, legible here" rather than one fixed fill — so the App's render edge
/// only picks the side, never invents a value.
public enum ActionColorScheme: String, CaseIterable, Equatable, Sendable {
    case light
    case dark
}

/// One swatch's sRGB fill as pure numbers (0…1), so the palette's legibility tuning
/// is Core data a `swift test` can *measure* rather than App vocabulary that can only
/// be eyeballed. The App turns a pair of these into a scheme-reactive `Color` at its
/// badge edge — the same defer-to-the-edge split the kind-derived tints already use.
public struct ActionColorComponents: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Builds a swatch from 8-bit channels — how the palette below is written, since
    /// hex-derived values are what a designer hands over.
    init(_ r: Int, _ g: Int, _ b: Int) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// WCAG relative luminance — the input to the contrast ratio below.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio between this fill and the **white** badge symbol drawn
    /// on it. The badge is a graphical object, so 3:1 (WCAG 1.4.11 non-text contrast)
    /// is the floor every palette entry must clear in both schemes — the arithmetic
    /// behind "tuned for legibility", enforced by `ActionColorTests`.
    var contrastRatioAgainstWhite: Double {
        1.05 / (relativeLuminance + 0.05)
    }
}

/// The curated **Action color** palette (CONTEXT.md → Action color; issue #243): the
/// closed set of named tints a user may give an Action, the glyph's sibling
/// customization. Ten tokens plus **Default** — which is the *absence* of a token,
/// not an eleventh case, so "no choice" and "the provider-kind-derived tint" are the
/// same state and an untouched action renders exactly as before.
///
/// A token, never a raw hex string: the stored value is one of these names, so the
/// actual fills stay centrally tuned here and a palette revision reaches every stored
/// action at once. Each token carries a **per-scheme** fill, both cleared against the
/// white badge symbol at ≥ 3:1 — the light swatches are the saturated mid-tones the
/// badge language already uses, the dark ones lifted just enough to hold their hue
/// against a dark background without washing the symbol out.
///
/// Raw values are a **persisted format** (the store column, the widget snapshot key),
/// so renaming a case must keep its raw value.
public enum ActionColor: String, CaseIterable, Equatable, Sendable {
    case red
    case orange
    /// The legible stand-in for yellow: a true yellow can never hold a white symbol
    /// (its contrast against white is ~1.4:1), so the palette ships the ochre that can.
    case amber
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    /// The neutral — for the actions whose identity isn't a hue (a settings link, a
    /// utility) but which still want to read apart from their provider's default.
    case graphite

    /// Everything one token *is*: its picker name and its two tuned fills. Deliberately
    /// **one** switch rather than three parallel ones (label / light / dark) — a new
    /// token then cannot be half-added, tuned for one appearance and forgotten in the
    /// other. Light values are the saturated mid-tones the badge language already uses;
    /// dark ones are lifted just enough to hold their hue against a dark background
    /// without washing the white symbol out.
    private var entry: (label: String, light: ActionColorComponents, dark: ActionColorComponents) {
        switch self {
        case .red:      return ("Red",      ActionColorComponents(211, 47, 47),   ActionColorComponents(229, 79, 79))
        case .orange:   return ("Orange",   ActionColorComponents(198, 93, 12),   ActionColorComponents(222, 116, 26))
        case .amber:    return ("Amber",    ActionColorComponents(166, 124, 0),   ActionColorComponents(180, 136, 6))
        case .green:    return ("Green",    ActionColorComponents(46, 125, 50),   ActionColorComponents(60, 152, 66))
        case .teal:     return ("Teal",     ActionColorComponents(0, 121, 128),   ActionColorComponents(10, 145, 152))
        case .blue:     return ("Blue",     ActionColorComponents(21, 101, 192),  ActionColorComponents(38, 122, 214))
        case .indigo:   return ("Indigo",   ActionColorComponents(69, 74, 178),   ActionColorComponents(92, 98, 204))
        case .purple:   return ("Purple",   ActionColorComponents(123, 60, 168),  ActionColorComponents(144, 78, 191))
        case .pink:     return ("Pink",     ActionColorComponents(193, 45, 108),  ActionColorComponents(214, 63, 128))
        case .graphite: return ("Graphite", ActionColorComponents(90, 96, 106),   ActionColorComponents(108, 115, 126))
        }
    }

    /// The human name shown beside the swatch in the editor's colour picker.
    public var label: String { entry.label }

    /// This token's fill for one appearance — the single place a name becomes numbers.
    public func components(for scheme: ActionColorScheme) -> ActionColorComponents {
        switch scheme {
        case .light: return entry.light
        case .dark: return entry.dark
        }
    }

    /// Resolves a **stored** token string to a palette entry, or `nil` for Default.
    /// The single tolerant read point every persisted surface goes through: an absent,
    /// blank, unknown (a future build's token), or hex-shaped value all resolve to
    /// Default — the kind-derived tint — so a synced record this build can't render
    /// degrades to today's behaviour rather than to a blank or a crash. Trimmed and
    /// case-folded so a hand-edited or migrated value still lands.
    public init?(token: String?) {
        guard let token else { return nil }
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, let match = ActionColor(rawValue: normalized) else { return nil }
        self = match
    }
}
