/// A parsed color as four **unit-interval channels** — the device-independent
/// value Core hands the App so a row can wear a color without the App re-parsing
/// the text that produced it (CONTEXT.md → Detected result; issue #217).
///
/// Deliberately not a platform color: Core stays UIKit/SwiftUI-free, so it carries
/// the numbers and the App maps them to a `SwiftUI.Color` at its badge edge — the
/// same defer-to-the-edge split as `ActionKind.symbol` (meaning in Core, drawing in
/// the App). Channels are `0...1` in **extended sRGB terms**, the range every
/// platform color initializer takes directly.
public struct RGBA: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    /// Opacity, `0` transparent to `1` opaque. A color notation that carries no
    /// alpha (a 3- or 6-digit hex) parses as fully opaque.
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Builds a color from four **8-bit** channel values (`0...255`) — the form
    /// every hex notation decodes to — normalizing each to the unit interval.
    public init(red8: Int, green8: Int, blue8: Int, alpha8: Int = 255) {
        self.init(
            red: Double(red8) / 255,
            green: Double(green8) / 255,
            blue: Double(blue8) / 255,
            alpha: Double(alpha8) / 255
        )
    }
}
