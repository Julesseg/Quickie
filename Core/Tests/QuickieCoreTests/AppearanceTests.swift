import Foundation
import Testing
@testable import QuickieCore

// Settings holds a single control: Appearance — Light / Dark / System,
// defaulting to System, persisted and applied app-wide (CONTEXT.md → Settings).
// The Core owns the value type and its persistence round-trip so the App layer
// only has to map a case to a SwiftUI color scheme.
struct AppearanceTests {

    @Test("appearance defaults to System")
    func defaultsToSystem() {
        #expect(Appearance.default == .system)
    }

    @Test("appearance round-trips through its stored raw value")
    func persistsByRawValue() {
        for appearance in [Appearance.system, .light, .dark] {
            #expect(Appearance(rawValue: appearance.rawValue) == appearance)
        }
    }

    @Test("an unknown stored value falls back to System")
    func unknownFallsBackToDefault() {
        #expect(Appearance(stored: "chartreuse") == .system)
        #expect(Appearance(stored: nil) == .system)
        #expect(Appearance(stored: "dark") == .dark)
    }
}
