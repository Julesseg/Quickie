import Foundation
import Testing
@testable import QuickieCore

// The UnitConverter is the offline half of the Dynamic Calculator Provider
// (issue #8): it parses a natural-language conversion ("20 mi to km") and
// evaluates it through Foundation `Measurement`, returning the converted value
// and its unit, or `nil` when the text is not a conversion it can serve.
// Currency is deliberately out of scope (network-dependent). These tests pin
// parsing, the unit families it knows, and the decline cases.
struct UnitConverterTests {

    @Test("converts miles to kilometres")
    func milesToKilometres() {
        let result = Units.convert("20 mi to km")
        #expect(result?.unit == "km")
        #expect(abs((result?.value ?? 0) - 32.1869) < 0.001)
    }

    @Test("converts pounds to kilograms with the \"in\" connector")
    func poundsToKilograms() {
        // The issue's worked example: 180 lb in kg.
        let result = Units.convert("180 lb in kg")
        #expect(result?.unit == "kg")
        #expect(abs((result?.value ?? 0) - 81.6466) < 0.001)
    }

    @Test("converts temperatures across the affine scale")
    func celsiusToFahrenheit() {
        // Temperature is not a simple ratio; Measurement handles the offset.
        let result = Units.convert("100 c to f")
        #expect(result?.unit == "°F")
        #expect(abs((result?.value ?? 0) - 212) < 0.001)
    }

    @Test("converts volumes")
    func litresToGallons() {
        let result = Units.convert("10 l to gal")
        #expect(result?.unit == "gal")
        #expect(abs((result?.value ?? 0) - 2.6417) < 0.001)
    }

    @Test("accepts full unit names and plurals")
    func spelledOutUnits() {
        let result = Units.convert("5 miles to kilometers")
        #expect(result?.unit == "km")
        #expect(abs((result?.value ?? 0) - 8.0467) < 0.001)
    }

    @Test("the formatted result pairs the value with its unit symbol")
    func formattedResult() {
        #expect(Units.convert("1 mi to km")?.formatted == "1.6093 km")
    }

    @Test("French connector and unit names convert: '5 m en pieds'")
    func frenchConnector() {
        // The Units connectors localize through the same keyword tables as the
        // date grammar (ADR 0036; issue #211).
        let result = Units.convert("5 m en pieds", tables: [.english, .french])
        #expect(result?.unit == "ft")
        #expect(abs((result?.value ?? 0) - 16.4042) < 0.001)
        // Accented full unit names fold onto the registry's spellings.
        #expect(Units.convert("5 mètres en pieds", tables: [.english, .french])?.unit == "ft")
    }

    @Test("Spanish and German connectors convert their languages' phrasings")
    func spanishAndGermanConnectors() {
        #expect(Units.convert("5 m a pies", tables: [.english, .spanish])?.unit == "ft")
        let miles = Units.convert("2 kilómetros en millas", tables: [.english, .spanish])
        #expect(miles?.unit == "mi")
        #expect(abs((miles?.value ?? 0) - 1.2427) < 0.001)
        #expect(Units.convert("5 m in fuß", tables: [.english, .german])?.unit == "ft")
        #expect(Units.convert("5 meter als fuß", tables: [.english, .german])?.unit == "ft")
    }

    @Test("English connectors keep working with a language table layered on")
    func englishConnectorsAreTheFloor() {
        // Dual accept (ADR 0036): localization work never breaks an English query.
        let result = Units.convert("5 m to ft", tables: [.english, .french])
        #expect(result?.unit == "ft")
        #expect(abs((result?.value ?? 0) - 16.4042) < 0.001)
    }

    @Test("a localized connector is gated by its table — English-only declines it")
    func localizedConnectorNeedsItsTable() {
        // "en" is only a connector once the French (or Spanish) table is active.
        #expect(Units.convert("5 m en pieds") == nil)
    }

    // MARK: - Six new families (issue #214)

    @Test("converts areas, including the acre example and the superscript spelling")
    func areaConversions() {
        // The issue's worked example: 2 acres → m². 1 acre = 4046.8564 m².
        let acres = Units.convert("2 acres to m2")
        #expect(acres?.unit == "m²")
        #expect(abs((acres?.value ?? 0) - 8093.7128) < 0.01)
        // The superscript spelling folds onto the "2" spelling.
        #expect(Units.convert("2 acres to m²")?.unit == "m²")
        // ft²/km²/mi²/hectares all resolve within the family.
        #expect(Units.convert("1 km² to hectares")?.unit == "ha")
        #expect(abs((Units.convert("1 km² to hectares")?.value ?? 0) - 100) < 0.001)
        #expect(Units.convert("10 ft2 to in2")?.unit == "in²")
        #expect(Units.convert("1 mi² to acres")?.unit == "acre")
    }

    @Test("converts speeds: km/h, mph, m/s, knots")
    func speedConversions() {
        // The issue's worked example: 100 km/h → mph ≈ 62.1371.
        let mph = Units.convert("100 km/h to mph")
        #expect(mph?.unit == "mph")
        #expect(abs((mph?.value ?? 0) - 62.1371) < 0.001)
        #expect(Units.convert("10 m/s to km/h")?.unit == "km/h")
        #expect(abs((Units.convert("10 m/s to km/h")?.value ?? 0) - 36) < 0.001)
        let knots = Units.convert("50 knots to km/h")
        #expect(knots?.unit == "km/h")
        #expect(abs((knots?.value ?? 0) - 92.6) < 0.001)
    }

    @Test("data storage is decimal by default: 1 gb to mb answers 1000")
    func dataStorageDecimalDefault() {
        let dec = Units.convert("1 gb to mb")
        #expect(dec?.unit == "MB")
        #expect(dec?.value == 1000)
    }

    @Test("binary data storage is reachable only by the explicit -ib spelling")
    func dataStorageBinaryExplicit() {
        // "gib"/"mib" are distinct registry rows with distinct symbols; the
        // -ib spelling answers 1024, the decimal spelling never does.
        let bin = Units.convert("1 gib to mib")
        #expect(bin?.unit == "MiB")
        #expect(bin?.value == 1024)
        // Decimal and binary coexist without collapsing into one another.
        #expect(Units.convert("1 gb to mb")?.value == 1000)
    }

    @Test("converts energy: J/kJ/cal/kcal/Wh/kWh")
    func energyConversions() {
        #expect(Units.convert("1 kj to j")?.value == 1000)
        #expect(abs((Units.convert("1 kcal to cal")?.value ?? 0) - 1000) < 0.001)
        // 1 kWh = 1000 Wh — Wh is a custom unit Foundation omits.
        #expect(Units.convert("1 kwh to wh")?.unit == "Wh")
        #expect(abs((Units.convert("1 kwh to wh")?.value ?? 0) - 1000) < 0.001)
    }

    @Test("converts pressure: bar/psi/atm/kPa/mmHg")
    func pressureConversions() {
        // 1 bar = 100 kPa.
        #expect(abs((Units.convert("1 bar to kpa")?.value ?? 0) - 100) < 0.001)
        // 1 atm ≈ 14.6959 psi — atm is a custom unit Foundation omits.
        let psi = Units.convert("1 atm to psi")
        #expect(psi?.unit == "psi")
        #expect(abs((psi?.value ?? 0) - 14.6959) < 0.001)
        // 1 atm ≈ 760 mmHg.
        #expect(abs((Units.convert("1 atm to mmHg")?.value ?? 0) - 760) < 0.5)
    }

    @Test("converts durations: seconds through weeks (a magnitude conversion, not Date & time)")
    func durationConversions() {
        // The issue's worked example: 3 h → min.
        let min = Units.convert("3 h to min")
        #expect(min?.unit == "min")
        #expect(min?.value == 180)
        #expect(Units.convert("120 s to min")?.value == 2)
        // Days and weeks are custom units Foundation's UnitDuration omits.
        #expect(Units.convert("2 weeks to days")?.unit == "d")
        #expect(Units.convert("2 weeks to days")?.value == 14)
        #expect(Units.convert("1 day to h")?.value == 24)
    }

    @Test("no fuel-economy units are recognized")
    func noFuelEconomy() {
        #expect(Units.convert("50 mpg to l/100km") == nil)
        #expect(Units.convert("8 l/100km to mpg") == nil)
    }

    @Test("the new families still decline cross-family requests")
    func newFamiliesGuardCrossFamily() {
        // Each new family is gated by the shared-family guard exactly as the
        // originals are: an area is not a speed, a byte is not a second.
        #expect(Units.convert("1 m2 to km/h") == nil)
        #expect(Units.convert("1 gb to h") == nil)
        #expect(Units.convert("1 bar to j") == nil)
        #expect(Units.convert("1 h to kg") == nil)
    }

    @Test("cross-family conversions decline")
    func crossFamilyDeclines() {
        // Miles measure length, kilograms mass — not convertible.
        #expect(Units.convert("20 mi to kg") == nil)
    }

    @Test("an unknown unit declines")
    func unknownUnitDeclines() {
        #expect(Units.convert("20 foo to km") == nil)
        #expect(Units.convert("20 mi to bar") == nil)
    }

    @Test("text that is not a conversion declines")
    func nonConversionDeclines() {
        #expect(Units.convert("23*7") == nil)
        #expect(Units.convert("hello world") == nil)
        #expect(Units.convert("") == nil)
        #expect(Units.convert("20 km") == nil)
    }
}
