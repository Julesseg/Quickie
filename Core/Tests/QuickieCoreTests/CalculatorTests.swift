import Foundation
import Testing
@testable import QuickieCore

// The Calculator is the pure arithmetic heart of the Dynamic Calculator
// Provider (issue #8): a string of math in, a number out, or `nil` when the
// text is not an expression it can evaluate. It never touches the pasteboard or
// the UI — it only computes — so every operator, precedence rule, and decline
// case is pinned here without a simulator. The custom evaluator carries no
// third-party dependency (ADR 0004 / issue #8: "custom evaluator").
struct CalculatorTests {

    @Test("multiplies two whole numbers")
    func multiplies() {
        #expect(Calculator.evaluate("23*7") == 161)
    }

    @Test("multiplication binds tighter than addition")
    func precedence() {
        #expect(Calculator.evaluate("2+3*4") == 14)
    }

    @Test("parentheses override precedence and powers raise")
    func parenthesesAndPower() {
        // The issue's worked example: (5+3)^2 → 64.
        #expect(Calculator.evaluate("(5+3)^2") == 64)
    }

    @Test("powers are right-associative")
    func powerRightAssociative() {
        // 2^(3^2) = 2^9 = 512, not (2^3)^2 = 64.
        #expect(Calculator.evaluate("2^3^2") == 512)
    }

    @Test("division yields a decimal result")
    func divisionDecimal() {
        #expect(Calculator.evaluate("10/4") == 2.5)
    }

    @Test("decimal literals evaluate")
    func decimalLiterals() {
        #expect(Calculator.evaluate("1.5+2.25") == 3.75)
    }

    @Test("a leading minus negates the expression")
    func unaryMinus() {
        #expect(Calculator.evaluate("-5+3") == -2)
    }

    @Test("a minus binds to the operand it precedes")
    func unaryMinusAfterOperator() {
        #expect(Calculator.evaluate("3*-2") == -6)
    }

    @Test("surrounding and interior whitespace is ignored")
    func whitespaceTolerant() {
        #expect(Calculator.evaluate("  12  *  2 ") == 24)
    }

    @Test("non-math text declines (returns nil)")
    func declinesNonMath() {
        #expect(Calculator.evaluate("hello") == nil)
        #expect(Calculator.evaluate("20 mi to km") == nil)
    }

    @Test("an empty or whitespace-only string declines")
    func declinesEmpty() {
        #expect(Calculator.evaluate("") == nil)
        #expect(Calculator.evaluate("   ") == nil)
    }

    @Test("a malformed expression declines")
    func declinesMalformed() {
        #expect(Calculator.evaluate("2+") == nil)
        #expect(Calculator.evaluate("(5+3") == nil)
        #expect(Calculator.evaluate("2 3") == nil)
    }

    @Test("division by zero declines rather than returning infinity")
    func declinesDivisionByZero() {
        #expect(Calculator.evaluate("1/0") == nil)
    }

    @Test("\"X% of Y\" reads as a fraction of Y")
    func percentOf() {
        // The issue's worked example: 15% of 200 → 30.
        #expect(Calculator.evaluate("15% of 200") == 30)
    }

    @Test("a bare percent is a hundredth")
    func barePercent() {
        #expect(Calculator.evaluate("50%") == 0.5)
    }

    @Test("adding a percent adds that fraction of the left side")
    func addPercent() {
        // The calculator convention: 200 + 10% means 200 plus 10% of 200.
        #expect(Calculator.evaluate("200 + 10%") == 220)
    }

    @Test("subtracting a percent removes that fraction of the left side")
    func subtractPercent() {
        #expect(Calculator.evaluate("200 - 10%") == 180)
    }
}
