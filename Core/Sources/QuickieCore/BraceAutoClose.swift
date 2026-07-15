import Foundation

/// The URL-template field's **brace typing rules** (CONTEXT.md → Custom Action):
/// the pure text transform behind the editor's auto-closing `{`. The editor feeds
/// every keystroke's before/after pair through `adjusted(replacing:with:)` and
/// replaces the field text when a rule fires — pure here so the tricky cases
/// (pastes, deletions, adjacent braces, coalesced keystrokes) are unit-tested
/// without a keyboard.
public enum BraceAutoClose {

    /// Returns the replacement text the field should show after an edit from
    /// `old` to `new`, or `nil` when the edit needs no adjustment.
    ///
    /// Both rules key on one **contiguous insertion** — a shared prefix and
    /// suffix covering the whole old text. Length is deliberately *not* limited
    /// to one character: fast typing (and XCUITest's synthesized bursts) reaches
    /// the binding as coalesced multi-character insertions, so the rules read the
    /// run's **last** character — the one the caret sits right behind. Any other
    /// edit (a deletion, a select-and-replace) passes through untouched.
    ///
    /// - Typing `{` auto-closes the pair: the returned text carries a `}`
    ///   immediately after the inserted run, which lands *behind* the caret, so
    ///   the caret ends up between the pair. Skipped when the next character is
    ///   already a `}` — that keystroke re-opens an existing pair, it doesn't
    ///   start one.
    /// - Typing `}` against the `}` sitting **after** the caret skips over it
    ///   instead of doubling: the run's own close is dropped, so the keystroke
    ///   reads as stepping past the auto-inserted brace. (A lone typed `}` also
    ///   skips against a `}` right *before* it — a single character's insertion
    ///   position inside a brace run is ambiguous — but a longer run never does:
    ///   its preceding text ending in `}` is just a completed token.) `}}` never
    ///   means anything in a `{name}` template, so the collapse is safe.
    public static func adjusted(replacing old: String, with new: String) -> String? {
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
            return String(closed)
        case "}":
            let closesAgainstNext = runEnd < newChars.count && newChars[runEnd] == "}"
            let loneCloseAfterClose = runEnd - runStart == 1
                && runStart > 0 && newChars[runStart - 1] == "}"
            guard closesAgainstNext || loneCloseAfterClose else { return nil }
            var collapsed = newChars
            collapsed.remove(at: runEnd - 1)
            return String(collapsed)
        default:
            return nil
        }
    }
}
