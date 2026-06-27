import Foundation

/// The pure arithmetic evaluator behind the Dynamic Calculator Provider (issue
/// #8). It parses a string of math and returns the numeric result, or `nil`
/// when the text is not an expression it understands — the signal the Provider
/// uses to *decline cleanly* rather than inject a spurious row. It is a custom
/// recursive-descent evaluator with **no third-party dependency** (ADR 0004).
///
/// The interface is one function (`evaluate`); the grammar, tokenizer, and
/// precedence rules are private. Callers depend only on "text in → number or
/// nil," never on how the number is derived.
public enum Calculator {

    /// Evaluates `expression` and returns its value, or `nil` when the input is
    /// not a well-formed arithmetic expression (empty, stray letters, a dangling
    /// operator, an unbalanced paren, or a division by zero). `nil` is the
    /// "this isn't math" answer the Provider needs to step aside.
    ///
    /// Percentages follow the everyday-calculator convention: a trailing `%` is
    /// a hundredth (`50%` → 0.5), `of` reads as multiplication so `15% of 200`
    /// is 30, and a percent on the right of `+`/`-` is taken *of the left side*
    /// so `200 + 10%` is 220.
    public static func evaluate(_ expression: String) -> Double? {
        var parser = Parser(expression)
        return parser.parse()
    }
}

/// A value flowing through the parser, tagged with whether it was written as a
/// percentage. The tag is what lets `+`/`-` apply a percent *relative to the
/// left operand* (`200 + 10%` → 220) while `*` and a bare percentage collapse
/// it to a plain hundredth (`15% of 200` → 30, `50%` → 0.5).
private struct Operand {
    var value: Double
    var isPercent: Bool

    /// The operand as a plain number: a percentage collapses to its hundredth,
    /// everything else passes through. Used everywhere except the relative
    /// `+`/`-` rule, which needs the raw percent to scale against the left side.
    var plain: Double { isPercent ? value / 100 : value }
}

/// A recursive-descent parser over a flat token stream. Standard precedence
/// climbing: expression (`+ -`) → term (`* /`, with `of` reading as `*`) →
/// power (`^`, right-assoc) → unary (`-`/`+`) → primary (number or
/// parenthesised group), each optionally carrying a trailing `%`.
private struct Parser {
    private let tokens: [Token]
    private var pos = 0

    init(_ source: String) {
        tokens = Token.tokenize(source) ?? []
        // A source that fails to tokenize yields no tokens, so `parse` sees an
        // empty stream and declines.
    }

    /// Parses a full expression and succeeds only when every token is consumed —
    /// trailing garbage (`2 3`, `2)`) is a decline, not a partial answer. A
    /// lone percentage collapses to its hundredth at the top level.
    mutating func parse() -> Double? {
        guard !tokens.isEmpty else { return nil }
        guard let result = parseExpression(), pos == tokens.count else { return nil }
        return result.plain
    }

    // MARK: - Grammar

    private mutating func parseExpression() -> Operand? {
        guard var left = parseTerm() else { return nil }
        while let op = peekOperator(in: ["+", "-"]) {
            advance()
            guard let right = parseTerm() else { return nil }
            let base = left.plain
            // A percentage on the right is taken *of the left side*; a plain
            // number is added or subtracted directly.
            let delta = right.isPercent ? base * right.value / 100 : right.value
            left = Operand(value: op == "+" ? base + delta : base - delta, isPercent: false)
        }
        return left
    }

    private mutating func parseTerm() -> Operand? {
        guard var left = parsePower() else { return nil }
        while let op = peekOperator(in: ["*", "/"]) {
            advance()
            guard let right = parsePower() else { return nil }
            let lhs = left.plain, rhs = right.plain
            if op == "/" {
                guard rhs != 0 else { return nil }
                left = Operand(value: lhs / rhs, isPercent: false)
            } else {
                left = Operand(value: lhs * rhs, isPercent: false)
            }
        }
        return left
    }

    private mutating func parsePower() -> Operand? {
        guard let base = parseUnary() else { return nil }
        guard peekOperator(in: ["^"]) != nil else { return base }
        advance()
        // Right-associative: the exponent is itself a power expression.
        guard let exponent = parsePower() else { return nil }
        return Operand(value: pow(base.plain, exponent.plain), isPercent: false)
    }

    private mutating func parseUnary() -> Operand? {
        if let op = peekOperator(in: ["+", "-"]) {
            advance()
            guard let operand = parseUnary() else { return nil }
            // Negation preserves the percent tag: `-10%` stays a percentage.
            return Operand(value: op == "-" ? -operand.value : operand.value, isPercent: operand.isPercent)
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Operand? {
        guard let token = current else { return nil }
        var operand: Operand
        switch token {
        case .number(let value):
            advance()
            operand = Operand(value: value, isPercent: false)
        case .open:
            advance()
            guard let inner = parseExpression() else { return nil }
            guard case .close = current else { return nil }
            advance()
            operand = inner
        default:
            return nil
        }
        // A trailing `%` turns the operand into a percentage.
        if case .percent = current {
            advance()
            operand.isPercent = true
        }
        return operand
    }

    // MARK: - Cursor

    private var current: Token? { pos < tokens.count ? tokens[pos] : nil }

    private mutating func advance() { pos += 1 }

    /// Returns the operator symbol when the next token is one of `symbols`,
    /// without consuming it.
    private func peekOperator(in symbols: Set<Character>) -> Character? {
        if case .op(let symbol) = current, symbols.contains(symbol) { return symbol }
        return nil
    }
}

/// One lexical unit of an arithmetic expression.
private enum Token: Equatable {
    case number(Double)
    case op(Character)   // + - * / ^
    case percent         // %
    case open            // (
    case close           // )

    /// Splits `source` into tokens, or `nil` when it contains a character the
    /// calculator does not recognise (a stray letter, say) — the lexical decline
    /// that keeps unit-conversion queries like "20 mi to km" out of the math
    /// path. The one word it accepts is `of`, which reads as multiplication so
    /// "15% of 200" parses.
    static func tokenize(_ source: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(source)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c.isNumber || c == "." {
                var literal = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    literal.append(chars[i])
                    i += 1
                }
                guard let value = Double(literal) else { return nil }
                tokens.append(.number(value))
            } else if c.isLetter {
                var word = ""
                while i < chars.count, chars[i].isLetter {
                    word.append(chars[i])
                    i += 1
                }
                guard word.lowercased() == "of" else { return nil }
                tokens.append(.op("*"))
            } else if "+-*/^".contains(c) {
                tokens.append(.op(c))
                i += 1
            } else if c == "%" {
                tokens.append(.percent)
                i += 1
            } else if c == "(" {
                tokens.append(.open)
                i += 1
            } else if c == ")" {
                tokens.append(.close)
                i += 1
            } else {
                return nil
            }
        }
        return tokens
    }
}
