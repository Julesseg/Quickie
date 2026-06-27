import Foundation

/// A physical key arrangement, reduced to the one question the forgiving
/// matcher asks of it: are two letters close enough that a thumb could hit one
/// while meaning the other? (ADR 0005 — keyboard-adjacency weighting.)
///
/// The Core stays platform-agnostic: it never touches `UITextInputMode`. The
/// App reads the active keyboard's language and resolves it to a layout via
/// `forLanguage(_:)`, then hands that layout to the matcher. iOS exposes no key
/// geometry, so we ship a handful of hardcoded tables and infer adjacency from
/// each letter's row/column position.
public struct KeyboardLayout: Sendable, Equatable {
    /// A human/debug name for the layout (also the equality key).
    public let name: String

    /// letter → (row, column) on this layout. Built once per table.
    private let positions: [Character: (row: Int, col: Int)]

    public static func == (lhs: KeyboardLayout, rhs: KeyboardLayout) -> Bool {
        lhs.name == rhs.name
    }

    /// Builds a layout from its three letter rows, top to bottom. Column is the
    /// index within the row; we deliberately ignore the small horizontal
    /// stagger between rows — chebyshev-distance-1 over (row, col) captures the
    /// neighbors that matter for typo tolerance without modelling exact pitch.
    private init(name: String, rows: [String]) {
        self.name = name
        var positions: [Character: (Int, Int)] = [:]
        for (row, letters) in rows.enumerated() {
            for (col, letter) in letters.enumerated() {
                positions[letter] = (row, col)
            }
        }
        self.positions = positions
    }

    /// True when `a` and `b` are distinct letters sitting within one key of each
    /// other (same-row neighbor or a diagonal/vertical neighbor). A letter is
    /// never adjacent to itself, and letters absent from this layout (digits,
    /// punctuation) are never adjacent.
    public func areAdjacent(_ a: Character, _ b: Character) -> Bool {
        guard a != b, let pa = positions[a], let pb = positions[b] else { return false }
        let dr = abs(pa.row - pb.row)
        let dc = abs(pa.col - pb.col)
        return dr <= 1 && dc <= 1
    }

    public static let qwerty = KeyboardLayout(
        name: "QWERTY",
        rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    )

    public static let azerty = KeyboardLayout(
        name: "AZERTY",
        rows: ["azertyuiop", "qsdfghjklm", "wxcvbn"]
    )

    public static let qwertz = KeyboardLayout(
        name: "QWERTZ",
        rows: ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
    )

    /// Resolves the active keyboard's primary language (a BCP-47 tag such as
    /// `"fr-FR"`, or `nil`/opaque for third-party keyboards) to the layout we
    /// ship for it. iOS exposes no key geometry, so we infer the table from the
    /// language and fall back to QWERTY for anything we don't recognize — the
    /// non-adjacency matcher layers still cover those cases (ADR 0005).
    public static func forLanguage(_ code: String?) -> KeyboardLayout {
        guard let primary = code?.split(separator: "-").first.map(String.init)?.lowercased() else {
            return .qwerty
        }
        switch primary {
        case "fr": return .azerty
        case "de": return .qwertz
        default: return .qwerty
        }
    }
}
