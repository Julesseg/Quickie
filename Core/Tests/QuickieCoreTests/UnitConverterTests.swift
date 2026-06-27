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
