import Foundation

/// The URL-template field's **brace typing rules** (CONTEXT.md → Custom Action):
/// the pure text transform behind the editor's auto-closing `{`. The editor feeds
/// every keystroke's before/after pair through `adjusted(replacing:with:)` and
/// replaces the field text when a rule fires — pure here so the tricky cases
/// (pastes, deletions, adjacent braces) are unit-tested without a keyboard.
public enum BraceAutoClose {

    /// Returns the replacement text the field should show after an edit from
    /// `old` to `new`, or `nil` when the edit needs no adjustment.
    ///
    /// Both rules key on a **single-character insertion** — any other edit (a
    /// paste, a deletion, a multi-character replace) passes through untouched:
    ///
    /// - Typing `{` auto-closes the pair: the returned text carries a `}`
    ///   immediately after the typed brace. The caret sits right after the `{`
    ///   when the rule fires, and the insertion lands *behind* it, so the caret
    ///   ends up between the pair. Skipped when the next character is already a
    ///   `}` — that keystroke re-opens an existing pair, it doesn't start one.
    /// - Typing `}` against an adjacent `}` **skips over** the existing close
    ///   instead of doubling it: the returned text is `old` unchanged, so the
    ///   keystroke reads as stepping past the auto-inserted brace. `}}` never
    ///   means anything in a `{name}` template, so the collapse is safe.
    public static func adjusted(replacing old: String, with new: String) -> String? {
        let oldChars = Array(old)
        let newChars = Array(new)
        guard newChars.count == oldChars.count + 1 else { return nil }

        // Locate the inserted character: the first index where the texts diverge.
        // (Inside a run of identical characters this lands at the run's end — the
        // string is the same whichever member of the run was typed.)
        var index = 0
        while index < oldChars.count && oldChars[index] == newChars[index] { index += 1 }
        // Verify the edit really is that one insertion — dropping the diverging
        // character must restore the old text exactly.
        guard Array(newChars[..<index] + newChars[(index + 1)...]) == oldChars else { return nil }

        switch newChars[index] {
        case "{":
            guard index + 1 == newChars.count || newChars[index + 1] != "}" else { return nil }
            var closed = newChars
            closed.insert("}", at: index + 1)
            return String(closed)
        case "}":
            let hasAdjacentClose = (index > 0 && newChars[index - 1] == "}")
                || (index + 1 < newChars.count && newChars[index + 1] == "}")
            return hasAdjacentClose ? old : nil
        default:
            return nil
        }
    }
}
