import Foundation

/// The app-wide appearance preference (CONTEXT.md → Settings): the single
/// control the Settings page holds. Light and Dark force a scheme; System
/// follows the device. The Core owns the value and its persistence so the App
/// only maps a case to a SwiftUI `ColorScheme?` (System → `nil`).
public enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// The default before the user chooses — follow the device (CONTEXT.md →
    /// Settings: "defaulting to System").
    public static let `default`: Appearance = .system

    /// Resolves a persisted raw value back to an `Appearance`, falling back to
    /// the default for anything missing or unrecognized — so a corrupt or
    /// absent stored value never leaves the app without a scheme.
    public init(stored raw: String?) {
        self = raw.flatMap(Appearance.init(rawValue:)) ?? .default
    }
}
