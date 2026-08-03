import Foundation
import Testing
@testable import QuickieCore

// `NumberBases` is the programmer-notation half of the Calculator (issue #216;
// CONTEXT.md → Computed): a bare `0x`/`0b`/`0o` literal answered in decimal,
// and an explicit "<number> to <base>" conversion answered in the target base
// with an unambiguous prefix. Like the Calculator it is pure — text in, an
// answer or `nil` out — so every accepted phrasing and every decline is pinned
// here without a simulator. The provider wiring lives in ComputedBasesTests.
struct NumberBasesTests {

    // MARK: - Explicit conversions

    @Test("a decimal converts to hex, prefixed and uppercase")
    func decimalToHex() {
        // The issue's worked example: 255 to hex → 0xFF.
        #expect(NumberBases.answer(for: "255 to hex") == .conversion("0xFF"))
    }

    @Test("a hex literal converts to binary, prefixed")
    func hexToBinary() {
        #expect(NumberBases.answer(for: "0xff to bin") == .conversion("0b11111111"))
    }

    @Test("a binary literal converts to decimal, bare")
    func binaryToDecimal() {
        // Decimal is the notation-free base, so its answer carries no prefix —
        // and staging `10` back into the input is inert, exactly like any other
        // bare number.
        #expect(NumberBases.answer(for: "0b1010 to dec") == .conversion("10"))
    }

    @Test("octal answers with an 0o prefix and reads one back")
    func octalRoundTrip() {
        #expect(NumberBases.answer(for: "255 to oct") == .conversion("0o377"))
        #expect(NumberBases.answer(for: "0o377 to hex") == .conversion("0xFF"))
    }

    @Test("the long base names are accepted too")
    func longBaseNames() {
        #expect(NumberBases.answer(for: "255 to hexadecimal") == .conversion("0xFF"))
        #expect(NumberBases.answer(for: "10 to binary") == .conversion("0b1010"))
        #expect(NumberBases.answer(for: "0xff to decimal") == .conversion("255"))
        #expect(NumberBases.answer(for: "255 to octal") == .conversion("0o377"))
    }

    @Test("every English unit connector introduces the target base")
    func englishConnectors() {
        // The connectors come from the same keyword tables the unit converter
        // uses (ADR 0036), so "to", "in", and "as" all read alike.
        #expect(NumberBases.answer(for: "255 in hex") == .conversion("0xFF"))
        #expect(NumberBases.answer(for: "255 as hex") == .conversion("0xFF"))
    }

    @Test("the device language's connector is accepted alongside English")
    func localizedConnector() {
        let tables: [DateKeywordTable] = [.english, .french]
        #expect(NumberBases.answer(for: "255 en hex", tables: tables) == .conversion("0xFF"))
        // English never stops parsing — the dual-accept floor.
        #expect(NumberBases.answer(for: "255 to hex", tables: tables) == .conversion("0xFF"))
        // …and a French word is not accepted on an English-only device.
        #expect(NumberBases.answer(for: "255 en hex") == nil)
    }

    @Test("localized base names resolve like the global unit registry")
    func localizedBaseNames() {
        // The base registry is global (the Units precedent): the *connector* is
        // what each language's table gates, so the names themselves resolve
        // everywhere, diacritics folded.
        #expect(NumberBases.answer(for: "255 to hexadécimal") == .conversion("0xFF"))
        #expect(NumberBases.answer(for: "10 to binär") == .conversion("0b1010"))
    }

    @Test("an identity conversion answers rather than declining")
    func identityConversion() {
        // "Show me this in that base" is a fair question even when the answer
        // is what was typed — and the answer still round-trips when staged.
        #expect(NumberBases.answer(for: "0xff to hex") == .conversion("0xFF"))
        #expect(NumberBases.answer(for: "255 to dec") == .conversion("255"))
    }

    @Test("the notation is case-insensitive on both sides")
    func caseInsensitive() {
        #expect(NumberBases.answer(for: "0XFF TO BIN") == .conversion("0b11111111"))
    }

    @Test("a negative value converts sign-magnitude, never two's complement")
    func negativeValue() {
        // No bitwise operators means no word size to complement against; a
        // minus sign in front of the prefixed magnitude is the honest reading,
        // and it re-parses when staged.
        #expect(NumberBases.answer(for: "-255 to hex") == .conversion("-0xFF"))
        #expect(NumberBases.answer(for: "-0xff") == .literal("-255"))
    }

    // MARK: - Bare literals

    @Test("a bare prefixed literal answers its decimal value")
    func bareLiteralAnswersDecimal() {
        // A prefixed literal is an explicit notation act, not a bare number, so
        // it earns a row where `42` earns none.
        #expect(NumberBases.answer(for: "0xff") == .literal("255"))
        #expect(NumberBases.answer(for: "0b1010") == .literal("10"))
        #expect(NumberBases.answer(for: "0o377") == .literal("255"))
    }

    @Test("a bare decimal number declines — the inert-bare-number principle")
    func bareDecimalDeclines() {
        #expect(NumberBases.answer(for: "42") == nil)
        #expect(NumberBases.answer(for: "3.14") == nil)
        #expect(NumberBases.answer(for: "-5") == nil)
    }

    // MARK: - Declines

    @Test("a fractional value declines rather than truncating")
    func fractionalDeclines() {
        #expect(NumberBases.answer(for: "3.5 to hex") == nil)
        #expect(NumberBases.answer(for: "0.5 to bin") == nil)
    }

    @Test("a unit conversion is not a base conversion — the branches never arbitrate")
    func unitConversionDeclines() {
        // `hex`/`bin`/`dec`/`oct` are not units and no unit is a base, so the
        // two `to` grammars are disjoint by construction: neither has to
        // out-rank the other.
        #expect(NumberBases.answer(for: "20 mi to km") == nil)
        #expect(NumberBases.answer(for: "5 kg to lb") == nil)
    }

    @Test("an unknown target base declines")
    func unknownBaseDeclines() {
        #expect(NumberBases.answer(for: "255 to base64") == nil)
        #expect(NumberBases.answer(for: "255 to roman") == nil)
    }

    @Test("a non-numeric source declines")
    func nonNumericSourceDeclines() {
        #expect(NumberBases.answer(for: "hello to hex") == nil)
        #expect(NumberBases.answer(for: "to hex") == nil)
    }

    @Test("a literal whose digits do not belong to its base declines")
    func invalidDigitsDecline() {
        #expect(NumberBases.answer(for: "0b1012") == nil)
        #expect(NumberBases.answer(for: "0o378") == nil)
        #expect(NumberBases.answer(for: "0xzz") == nil)
        #expect(NumberBases.answer(for: "0x") == nil)
    }

    @Test("a value too large to hold declines rather than wrapping")
    func overflowDeclines() {
        #expect(NumberBases.answer(for: "99999999999999999999999 to hex") == nil)
        #expect(NumberBases.answer(for: "0xffffffffffffffffff") == nil)
    }

    @Test("empty and whitespace-only text declines")
    func emptyDeclines() {
        #expect(NumberBases.answer(for: "") == nil)
        #expect(NumberBases.answer(for: "   ") == nil)
    }
}
