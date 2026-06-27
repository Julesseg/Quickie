import Foundation
import Testing
@testable import QuickieCore

// The CalculatorProvider is the Dynamic Provider that inspects the live query
// and, when it parses as math or a unit conversion, injects a single result row
// whose main action copies the answer (issue #8 / CONTEXT.md → Dynamic
// Provider). These tests pin what the row says, what tapping it does, and that
// the provider declines cleanly — no spurious rows — for everything else.
struct CalculatorProviderTests {

    private let provider = CalculatorProvider()

    @Test("a math query yields one result whose main action copies the answer")
    func mathResultCopiesAnswer() {
        let results = provider.candidates(for: "23*7")
        #expect(results.count == 1)
        #expect(results.first?.title == "161")
        #expect(results.first?.run() == .copyText("161"))
    }

    @Test("a conversion query yields one result that copies the formatted answer")
    func conversionResultCopiesAnswer() {
        let results = provider.candidates(for: "20 mi to km")
        #expect(results.count == 1)
        // The row's title is the formatted conversion, and its main action copies
        // exactly what it shows — asserted without pinning the exact float, which
        // depends on Foundation's conversion factors.
        let title = try? #require(results.first?.title)
        #expect(title?.hasSuffix(" km") == true)
        #expect(results.first?.run() == .copyText(title ?? ""))
    }

    @Test("the injected result is a Dynamic Provider result, not a Fallback")
    func resultIsDynamicNonFallback() {
        // Dynamic kind + non-fallback is what the SearchEngine boosts to the top.
        #expect(provider.kind == .dynamic)
        #expect(provider.candidates(for: "23*7").first?.isFallback == false)
        #expect(provider.candidates(for: "23*7").first?.outputType == .number)
    }

    @Test("the row shows the originating expression as its subtitle")
    func resultSubtitleIsExpression() {
        #expect(provider.candidates(for: "2+2").first?.subtitle == "2+2")
    }

    @Test("a non-math, non-conversion query declines — no spurious row")
    func declinesNonMath() {
        #expect(provider.candidates(for: "github").isEmpty)
        #expect(provider.candidates(for: "hello world").isEmpty)
        #expect(provider.candidates(for: "").isEmpty)
        #expect(provider.candidates(for: "   ").isEmpty)
    }

    @Test("a bare number is not a calculation — no spurious row")
    func declinesBareNumber() {
        #expect(provider.candidates(for: "42").isEmpty)
        #expect(provider.candidates(for: "3.14").isEmpty)
    }

    @Test("a malformed expression declines")
    func declinesMalformed() {
        #expect(provider.candidates(for: "2+").isEmpty)
        #expect(provider.candidates(for: "1/0").isEmpty)
    }
}
