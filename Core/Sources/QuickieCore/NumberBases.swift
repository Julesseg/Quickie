import Foundation

/// The programmer-notation half of the Calculator (issue #216; CONTEXT.md →
/// Computed). It owns everything the app knows about number bases:
///
/// - which prefix opens which radix (`0x` → 16, `0b` → 2, `0o` → 8) — the hook
///   `Calculator`'s tokenizer uses so a base literal is just another way to
///   write a number inside ordinary arithmetic (`0xff + 1` → 256);
/// - the base names an explicit conversion can target (`hex`, `bin`, `dec`,
///   `oct`, plus their long and localized spellings);
/// - how an answer is written back out — **prefixed**, so `255 to hex` answers
///   `0xFF` and the staged text stays unambiguous and re-parseable.
///
/// There are deliberately **no bitwise operators** and `^` stays power: with no
/// word size to complement against, a negative value converts sign-magnitude
/// (`-255 to hex` → `-0xFF`) rather than pretending to be a machine word.
///
/// The interface is one function (`answer(for:tables:)`) plus the tokenizer's
/// prefix hook; the two registries, the shapes they match, and the formatting
/// are private. It returns `nil` for anything that is not base notation — the
/// clean decline the Provider needs to step aside, and what keeps the `to`
/// connector from ever arbitrating with the unit converter: no unit is a base
/// and no base is a unit, so at most one of the two grammars matches a query.
public enum NumberBases {

    /// A base-notation answer, ready to show and to copy — the text is the row
    /// title, and copy-and-stage puts exactly it back in the input.
    ///
    /// The two cases name what the user did, and the distinction is the one the
    /// inert-bare-number principle turns on: a *prefixed literal typed alone*
    /// is an explicit notation act and earns a row, where `42` earns none.
    public enum Answer: Equatable, Sendable {
        /// A bare prefixed literal, answered in decimal (`0xff` → `255`).
        case literal(String)
        /// An explicit conversion, answered in the target base with its prefix
        /// (`255 to hex` → `0xFF`; decimal, the notation-free base, is bare).
        case conversion(String)
    }

    /// Reads `query` as base notation and returns its answer, or `nil` when it
    /// is not base notation at all.
    ///
    /// Two shapes are accepted: a bare prefixed literal on its own, and an
    /// explicit conversion — `<number> <connector> <base>`, where the number may
    /// itself be a prefixed literal. An identity conversion (`255 to dec`,
    /// `0xff to hex`) answers rather than declines: "show me this in that base"
    /// is a fair question even when the answer is what was typed. A fractional
    /// value declines (there is no honest hex for `3.5`), as does a value too
    /// large to hold, an unknown base name, and digits that do not belong to
    /// their literal's base.
    ///
    /// The connector words come from the accepted date keyword tables (ADR
    /// 0036; issue #211) — the same ones the unit converter reads — so "255 to
    /// hex" works everywhere and "255 en hex" on a French device. The base
    /// *names* are a global registry, exactly as the unit registry is.
    public static func answer(for query: String, tables: [DateKeywordTable] = [.english]) -> Answer? {
        if let value = parseLiteral(query) {
            return .literal(String(value))
        }
        guard let request = parseConversion(query, tables: tables) else { return nil }
        return .conversion(format(request.value, in: request.radix))
    }

    // MARK: - Notation

    /// Every base with a literal notation, keyed by the letter its prefix uses.
    /// This is the single declaration of the notation: the shapes below are
    /// built from it, `format` writes prefixes back out of it, and
    /// `radix(forPrefix:)` is how `Calculator`'s tokenizer reads it.
    private static let prefixes: [Character: Int] = ["x": 16, "b": 2, "o": 8]

    /// The radix a base prefix opens — `x` → 16, `b` → 2, `o` → 8 — or `nil`
    /// for any other character. The hook `Calculator`'s tokenizer uses to
    /// recognise a literal mid-expression, so which prefix means what is known
    /// in exactly one place.
    static func radix(forPrefix letter: Character) -> Int? {
        prefixes[Character(letter.lowercased())]
    }

    /// The prefix a radix is written with, or `""` for decimal — the
    /// notation-free base, which is what makes `0b1010 to dec` → `10` land back
    /// in the input inert, exactly like any other bare number.
    private static func notation(for radix: Int) -> String {
        prefixes.first { $0.value == radix }.map { "0\($0.key)" } ?? ""
    }

    // MARK: - Parsing

    /// A parsed conversion: the value to render, and the radix to render it in.
    private struct Request {
        let value: Int
        let radix: Int
    }

    /// The four words a matched shape hands back — the sign and the number
    /// always, the connector and target base only for a conversion (empty for a
    /// bare literal). Both shapes below capture them in this order.
    private struct Fields {
        let sign: String
        let number: String
        let connector: String
        let base: String
    }

    /// A prefixed literal standing alone — the explicit notation act that earns
    /// a decimal row where a plain digit run earns none.
    private static let literalPattern = shape(#"^\s*(-?)\s*(\#(literal))\s*$"#)

    /// `<number> <connector> <base>` — the explicit conversion. The number is a
    /// prefixed literal or a plain digit run, optionally signed; a fractional
    /// value simply does not match, which is how `3.5 to hex` declines. The
    /// connector and base words are validated against the tables and the
    /// registry *after* the match, so the shape stays language-independent —
    /// the same split `Units` makes.
    private static let conversionPattern = shape(#"^\s*(-?)\s*(\#(literal)|[0-9]+)\s+(\p{L}+)\s+(\p{L}+)\s*$"#)

    /// The literal alternation (`0[xbo][0-9a-z]+`), assembled from `prefixes`
    /// so a new notation never has to be spelled into a pattern. Digits are
    /// matched loosely and validated against the radix, so `0b1012` declines
    /// rather than half-parsing to `0b101`.
    private static let literal = "0[" + prefixes.keys.sorted().map(String.init).joined() + "][0-9a-z]+"

    private static func shape(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func parseLiteral(_ query: String) -> Int? {
        guard let fields = fields(literalPattern, in: query) else { return nil }
        return integer(fields)
    }

    private static func parseConversion(_ query: String, tables: [DateKeywordTable]) -> Request? {
        guard let fields = fields(conversionPattern, in: query) else { return nil }
        guard DateKeywordTable.accepts(connector: fields.connector, in: tables) else { return nil }
        guard let radix = registry[DateKeywordTable.folded(fields.base)] else { return nil }
        guard let value = integer(fields) else { return nil }
        return Request(value: value, radix: radix)
    }

    /// Matches `pattern` against `query` and names its capture groups, or
    /// returns `nil` when it does not match. Groups the shape does not capture
    /// come back empty.
    private static func fields(_ pattern: NSRegularExpression, in query: String) -> Fields? {
        let text = query.lowercased()
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }
        func group(_ index: Int) -> String {
            guard index < match.numberOfRanges,
                  let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
        return Fields(sign: group(1), number: group(2), connector: group(3), base: group(4))
    }

    /// The signed value of a matched number token, or `nil` when its digits do
    /// not belong to its base (`0b1012`) or the value is too large to hold —
    /// both declines, never a truncation or a wrap.
    private static func integer(_ fields: Fields) -> Int? {
        let token = fields.number
        var radix = 10
        var digits = Substring(token)
        if token.count > 2, token.hasPrefix("0"),
           let prefixed = self.radix(forPrefix: token[token.index(after: token.startIndex)]) {
            radix = prefixed
            digits = token.dropFirst(2)
        }
        guard let magnitude = Int(digits, radix: radix) else { return nil }
        return fields.sign == "-" ? -magnitude : magnitude
    }

    // MARK: - Base registry

    /// Every accepted base name mapped to its radix, diacritic-folded. The
    /// registry is global — the *connector* is what each language's table gates
    /// (the `Units` precedent) — so the FR/ES/DE spellings sit beside the
    /// English ones. A new base is a `prefixes` entry plus its names here;
    /// nothing in the parser changes.
    private static let registry: [String: Int] = {
        var map: [String: Int] = [:]

        func add(_ aliases: [String], _ radix: Int) {
            for alias in aliases { map[alias] = radix }
        }

        add(["hex", "hexadecimal"], 16)
        add(["bin", "binary", "binaire", "binario", "binar"], 2)
        add(["oct", "octal", "oktal"], 8)
        add(["dec", "decimal", "dezimal"], 10)

        return map
    }()

    // MARK: - Formatting

    /// Renders `value` in `radix`, prefixed. The sign rides outside the prefix
    /// (`-0xFF`, not `0x-FF`) so the answer re-parses as a literal when staged,
    /// and the magnitude is taken unsigned so the most-negative value does not
    /// overflow on its way to a string. Digits above 9 are letters — only hex
    /// has any — and read better uppercased.
    private static func format(_ value: Int, in radix: Int) -> String {
        let digits = String(value.magnitude, radix: radix, uppercase: radix > 10)
        return (value < 0 ? "-" : "") + notation(for: radix) + digits
    }
}
