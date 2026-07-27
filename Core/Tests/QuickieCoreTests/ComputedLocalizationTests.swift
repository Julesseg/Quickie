import Foundation
import Testing
@testable import QuickieCore

// Date & time localization at the provider seam (issue #211; ADR 0036): the
// Computed provider reads the device language off its injected calendar's
// locale and layers exactly that language's keyword table on the English
// floor — for the date grammar *and* the Units connectors alike. Grammar
// coverage lives in DateGrammarTests and UnitConverterTests; these tests pin
// the wiring: which tables are active for which device, and that English
// keeps working everywhere.
struct ComputedLocalizationTests {

    /// Mid-morning on **Wednesday, July 15, 2026** — the same fixed "now" as
    /// DateGrammarTests.
    private static let now = calendar(languageRegion: "en_US")
        .date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 9, minute: 30))!

    private static func calendar(languageRegion: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: languageRegion)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func provider(languageRegion: String) -> ComputedProvider {
        ComputedProvider(calendar: Self.calendar(languageRegion: languageRegion), now: { Self.now })
    }

    @Test("a French device parses French date phrases into the usual rows")
    func frenchDeviceParsesFrench() {
        let provider = provider(languageRegion: "fr_FR")

        // "3 semaines à partir de vendredi" answers August 7, 2026 — one
        // copy-only date row, formatted per the device (French) locale.
        let dateRows = provider.candidates(for: "3 semaines à partir de vendredi")
        let expected = Self.calendar(languageRegion: "fr_FR")
            .date(from: DateComponents(year: 2026, month: 8, day: 7))!
        let formatted = DateGrammar.formatted(expected, calendar: Self.calendar(languageRegion: "fr_FR"))
        #expect(dateRows.map(\.id) == ["date.relative"])
        #expect(dateRows.first?.title == formatted)

        // "jours jusqu'à noël" answers a count — full Calculator manners.
        let countRows = provider.candidates(for: "jours jusqu'à noël")
        #expect(countRows.map(\.id) == ["date.count"])
        #expect(countRows.first?.run() == .copyAndStage(text: "163"))
    }

    @Test("a French device converts '5 m en pieds' through the localized connector")
    func frenchDeviceConvertsUnits() {
        let rows = provider(languageRegion: "fr_FR").candidates(for: "5 m en pieds")
        #expect(rows.map(\.id) == ["calc.conversion"])
        #expect(rows.first?.title == "16 ft 4.9 in")
    }

    @Test("English keeps working on every localized device — the dual-accept floor")
    func englishParsesOnLocalizedDevices() {
        for language in ["fr_FR", "es_ES", "de_DE"] {
            let provider = provider(languageRegion: language)
            #expect(provider.candidates(for: "days until dec 25").first?.run() == .copyAndStage(text: "163"))
            #expect(provider.candidates(for: "5 m to ft").first?.title == "16 ft 4.9 in")
        }
    }

    @Test("an English device does not accept the localized grammars")
    func englishDeviceDeclinesLocalizedPhrases() {
        let provider = provider(languageRegion: "en_US")
        #expect(provider.candidates(for: "3 semaines à partir de vendredi").isEmpty)
        #expect(provider.candidates(for: "5 m en pieds").isEmpty)
    }

    @Test("only the device language layers on — a French phrase declines on a Spanish device")
    func layersDoNotStack() {
        let provider = provider(languageRegion: "es_ES")
        #expect(provider.candidates(for: "jours jusqu'à noël").isEmpty)
        // …while the Spanish equivalents parse.
        #expect(provider.candidates(for: "días hasta navidad").first?.run() == .copyAndStage(text: "163"))
        #expect(provider.candidates(for: "5 m en pies").first?.title == "16 ft 4.9 in")
    }
}
