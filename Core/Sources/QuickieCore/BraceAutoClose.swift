import Foundation

/// The URL-template field's **brace typing rules** (CONTEXT.md → Custom Action):
/// the pure text transform behind the editor's auto-closing `{`. The editor feeds
/// every keystroke's before/after pair through `adjusted(replacing:with:)` and,
/// when a rule fires, replaces the field text **and re-places the caret** from the
/// returned offset — pure here so the tricky cases (pastes, deletions, adjacent
/// braces, coalesced keystrokes, caret math) are unit-tested without a keyboard.
public enum BraceAutoClose {

    /// One applied brace rule: the replacement `text` and the character offset
    /// the caret must sit at afterwards. The caret comes back explicitly because
    /// the platform resets a text field's caret to the **end** whenever its text
    /// is replaced programmatically — the editor re-places it from `caretOffset`:
    /// between the pair after an auto-close, just past the close after a
    /// skip-over.
    public struct Adjustment: Equatable, Sendable {
        public let text: String
        public let caretOffset: Int

        public init(text: String, caretOffset: Int) {
            self.text = text
            self.caretOffset = caretOffset
        }
    }

    /// Returns the replacement the field should apply after an edit from `old`
    /// to `new`, or `nil` when the edit needs no adjustment.
    ///
    /// Both rules key on one **contiguous insertion** — a shared prefix and
    /// suffix covering the whole old text. Length is deliberately *not* limited
    /// to one character: fast typing (and XCUITest's synthesized bursts) reaches
    /// the binding as coalesced multi-character insertions, so the rules read the
    /// run's **last** character — the one the caret sits right behind. Any other
    /// edit (a deletion, a select-and-replace) passes through untouched.
    ///
    /// - Typing `{` auto-closes the pair: the returned text carries a `}`
    ///   immediately after the inserted run, and the caret offset points between
    ///   the pair. Skipped when the next character is already a `}` — that
    ///   keystroke re-opens an existing pair, it doesn't start one.
    /// - Typing `}` against the `}` sitting **after** the caret skips over it
    ///   instead of doubling: the run's own close is dropped and the caret lands
    ///   just past the existing one. (A lone typed `}` also skips against a `}`
    ///   right *before* it — a single character's insertion position inside a
    ///   brace run is ambiguous — but a longer run never does: its preceding text
    ///   ending in `}` is just a completed token.) `}}` never means anything in a
    ///   `{name}` template, so the collapse is safe.
    public static func adjusted(replacing old: String, with new: String) -> Adjustment? {
        let oldChars = Array(old)
        let newChars = Array(new)
        guard newChars.count > oldChars.count else { return nil }

        // The edit must be one contiguous insertion: a maximal shared prefix,
        // then a shared suffix capped so the two never overlap, together covering
        // the whole old text.
        var prefix = 0
        while prefix < oldChars.count && oldChars[prefix] == newChars[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldChars.count - prefix
            && oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }
        guard prefix + suffix == oldChars.count else { return nil }

        let runStart = prefix
        let runEnd = newChars.count - suffix

        switch newChars[runEnd - 1] {
        case "{":
            guard runEnd == newChars.count || newChars[runEnd] != "}" else { return nil }
            var closed = newChars
            closed.insert("}", at: runEnd)
            // The caret stays where the typed `{` left it — between the pair.
            return Adjustment(text: String(closed), caretOffset: runEnd)
        case "}":
            let closesAgainstNext = runEnd < newChars.count && newChars[runEnd] == "}"
            let loneCloseAfterClose = runEnd - runStart == 1
                && runStart > 0 && newChars[runStart - 1] == "}"
            guard closesAgainstNext || loneCloseAfterClose else { return nil }
            var collapsed = newChars
            collapsed.remove(at: runEnd - 1)
            // The caret steps past the `}` that was skipped over: the one after
            // the collapsed run (`closesAgainstNext`), or — for a lone `}` whose
            // detected position trails an existing close — the run's own slot.
            return Adjustment(
                text: String(collapsed),
                caretOffset: closesAgainstNext ? runEnd : runEnd - 1
            )
        default:
            return nil
        }
    }
}
