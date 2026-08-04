import Foundation
import Testing
@testable import QuickieCore

// The Computed provider's **base-literal** rows (issue #216; CONTEXT.md →
// Computed): arithmetic over `0x`/`0b` literals answers decimal through the
// ordinary math row, an explicit "<number> to <base>" answers in the target
// base, and a bare prefixed literal alone fires its decimal value. These pin
// the wiring — which row fires, what it says, what tapping it does, and which
// toggle gates it; the grammar itself is pinned in NumberBasesTests.
struct ComputedBasesTests {

    private let provider = ComputedProvider()

    @Test("a base literal inside arithmetic answers through the math row")
    func baseLiteralArithmetic() {
        let math = provider.candidates(for: "0xff + 1")
        #expect(math.map(\.id) == ["calc.math"])
        #expect(math.first?.title == "256")

        #expect(provider.candidates(for: "0b1010 * 2").first?.title == "20")
    }

    @Test("an explicit conversion answers in the target base, prefixed")
    func explicitConversion() {
        let rows = provider.candidates(for: "255 to hex")
        #expect(rows.map(\.id) == ["calc.base"])
        #expect(rows.first?.title == "0xFF")
        #expect(rows.first?.subtitle == "255 to hex")

        #expect(provider.candidates(for: "0xff to bin").first?.title == "0b11111111")
        #expect(provider.candidates(for: "0b1010 to dec").first?.title == "10")
    }

    @Test("a bare prefixed literal fires its decimal row; a bare number still fires nothing")
    func bareLiteralFiresDecimalRow() {
        let rows = provider.candidates(for: "0xff")
        #expect(rows.map(\.id) == ["calc.literal"])
        #expect(rows.first?.title == "255")

        // The inert-bare-number principle survives: a prefixed literal is an
        // explicit notation act, a plain digit run is not.
        #expect(provider.candidates(for: "42").isEmpty)
        #expect(provider.candidates(for: "255").isEmpty)
    }

    @Test("a prefixed answer re-parses when staged back into the input")
    func answerRoundTrips() {
        // Copy-and-stage means the answer lands back in the field, so what the
        // row shows has to be something the grammar reads again.
        let converted = try? #require(provider.candidates(for: "255 to hex").first?.title)
        #expect(converted == "0xFF")
        #expect(provider.candidates(for: converted ?? "").first?.title == "255")
    }

    @Test("base rows keep Calculator manners — copy-and-stage, number content")
    func baseRowsKeepCalculatorManners() {
        for query in ["255 to hex", "0xff"] {
            let row = try? #require(provider.candidates(for: query).first)
            #expect(row?.content == .number)
            #expect(row?.outputType == .number)
            #expect(row?.run() == .copyAndStage(text: row?.title ?? ""))
        }
    }

    @Test("the Math toggle gates every base row — no new setting")
    func mathToggleGatesBaseRows() {
        let off = ComputedProvider(math: false)
        #expect(off.candidates(for: "0xff + 1").isEmpty)
        #expect(off.candidates(for: "255 to hex").isEmpty)
        #expect(off.candidates(for: "0xff").isEmpty)

        // The unit-conversion toggle is a different switch and leaves bases alone.
        let noUnits = ComputedProvider(unitConversion: false)
        #expect(noUnits.candidates(for: "255 to hex").first?.title == "0xFF")
    }

    @Test("the `to` connector needs no arbitration between bases and units")
    func toConnectorNeverArbitrates() {
        // A unit conversion still answers as a unit conversion, and a base
        // conversion as a base conversion: the two grammars are disjoint, so
        // neither branch has to out-rank the other.
        #expect(provider.candidates(for: "20 mi to km").map(\.id) == ["calc.conversion"])
        #expect(provider.candidates(for: "255 to hex").map(\.id) == ["calc.base"])
    }

    @Test("a fractional value declines rather than truncating")
    func fractionalConversionDeclines() {
        #expect(provider.candidates(for: "3.5 to hex").isEmpty)
    }

    @Test("bitwise queries fire nothing at all")
    func bitwiseFiresNothing() {
        #expect(provider.candidates(for: "6 & 3").isEmpty)
        #expect(provider.candidates(for: "1 << 2").isEmpty)
        #expect(provider.candidates(for: "6 xor 3").isEmpty)
        // …while `^` still answers as a power.
        #expect(provider.candidates(for: "2^10").first?.title == "1024")
    }
}
