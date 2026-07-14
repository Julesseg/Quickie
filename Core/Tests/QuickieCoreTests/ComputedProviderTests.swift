import Foundation
import Testing
@testable import QuickieCore

// The ComputedProvider is the boosted-dynamic Provider that inspects the live
// query and, when it parses as math or a unit conversion, injects a result row
// whose main action copies the answer (issue #8 / CONTEXT.md → Computed). These
// tests pin the Calculator half — what the row says, what tapping it does, and
// that the provider declines cleanly for everything else; the Detected result
// half lives in ComputedDetectionTests.
struct ComputedProviderTests {

    private let provider = ComputedProvider()

    @Test("a math query yields one result whose main action copies and stages the answer")
    func mathResultCopiesAndStagesAnswer() {
        let results = provider.candidates(for: "23*7")
        #expect(results.count == 1)
        #expect(results.first?.title == "161")
        // The main action both copies the answer and stages it back into the input
        // so the user keeps calculating (CONTEXT.md → main action).
        #expect(results.first?.run() == .copyAndStage(text: "161"))
    }

    @Test("a conversion query yields one result that copies and stages the formatted answer")
    func conversionResultCopiesAndStagesAnswer() {
        let results = provider.candidates(for: "20 mi to km")
        #expect(results.count == 1)
        // The row's title is the formatted conversion, and its main action copies
        // and stages exactly what it shows — asserted without pinning the exact
        // float, which depends on Foundation's conversion factors.
        let title = try? #require(results.first?.title)
        #expect(title?.hasSuffix(" km") == true)
        #expect(results.first?.run() == .copyAndStage(text: title ?? ""))
    }

    @Test("the injected result declares number content, not the text it copies")
    func resultDeclaresNumberContent() {
        // The Calculator copies *text* but its content reads as `.number` (ADR
        // 0017): proof content is a declared property, not derived from the
        // copy-text outcome. Its secondary actions are the universal copy/share pair
        // plus the id-keyed Copy action deeplink every row earns (issue #120).
        let result = provider.candidates(for: "23*7").first
        #expect(result?.content == .number)
        #expect(result.map { secondaryActions(for: $0.content) } == [.copy, .share, .copyDeeplink])
    }

    @Test("the injected result is a Dynamic Provider result, not a Fallback")
    func resultIsDynamicNonFallback() {
        // Dynamic kind + non-fallback is what the SearchEngine boosts to the top.
        #expect(provider.kind == .dynamic)
        #expect(provider.candidates(for: "23*7").first?.isFallbackEligible == false)
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

    @Test("a negative bare number declines — a staged negative answer stays inert")
    func declinesLeadingNegativeNumber() {
        // A leading `-` is a sign, not an operator, so a negative literal reads as
        // a bare number and declines like `42` does. This keeps a staged negative
        // answer from re-triggering the Calculator on itself: `2 - 7` computes to
        // `-5`, and staging `-5` back into the input declines — inert, exactly like
        // staging `2+2` → `4`.
        #expect(provider.candidates(for: "-5").isEmpty)
        #expect(provider.candidates(for: "-3.14").isEmpty)
        #expect(provider.candidates(for: "2 - 7").first?.title == "-5")
        #expect(provider.candidates(for: "-5").isEmpty)
    }

    @Test("a leading sign in front of an operator is still a calculation")
    func leadingSignWithOperatorStillCalculates() {
        // Only the *leading* `+`/`-` is exempted: an expression that opens with a
        // sign but carries a real operator (or a paren) still calculates.
        #expect(provider.candidates(for: "-5+3").first?.title == "-2")
        #expect(provider.candidates(for: "-(2+3)").first?.title == "-5")
    }

    @Test("a malformed expression declines")
    func declinesMalformed() {
        #expect(provider.candidates(for: "2+").isEmpty)
        #expect(provider.candidates(for: "1/0").isEmpty)
    }

    @Test("a finite-but-large result never renders as inf")
    func largeResultIsFinite() {
        // 10^300 is finite, so the calculator returns it; the formatted row must
        // not collapse to "inf" when the value is scaled for rounding.
        let title = provider.candidates(for: "10^300").first?.title
        #expect(title != nil)
        #expect(title != "inf")
        #expect(title?.contains("inf") == false)
        #expect(title?.hasPrefix("1") == true)
    }

    @Test("the unit-conversion toggle gates conversions but never arithmetic")
    func unitConversionToggleGatesConversions() {
        // The schema's new Calculator unit-conversion toggle (issue #69 AC #4) takes
        // effect here: off, the provider answers arithmetic only and declines a
        // conversion query (rather than injecting a spurious row); on, both work.
        let mathOnly = ComputedProvider(unitConversion: false)
        #expect(mathOnly.candidates(for: "20 mi to km").isEmpty)
        // Arithmetic is untouched by the conversion toggle.
        #expect(mathOnly.candidates(for: "23*7").first?.title == "161")

        // On (the default) still answers conversions.
        #expect(!provider.candidates(for: "20 mi to km").isEmpty)
    }

    @Test("\"of\" only triggers as a whole word, not inside another word")
    func ofIsWordBounded() {
        // The "of" calculation gate must not fire on words that merely contain
        // the letters; "profile"/"off" are not calculations.
        #expect(provider.candidates(for: "profile").isEmpty)
        #expect(provider.candidates(for: "off").isEmpty)
        // …but it still triggers as a real word.
        #expect(provider.candidates(for: "15% of 200").first?.title == "30")
    }
}
