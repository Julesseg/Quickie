import Foundation

/// The **single-line rule** for a wrapping text field (CONTEXT.md → Custom Action):
/// the Custom Action editor's URL field is a vertical-axis field so a long template
/// wraps instead of scrolling sideways, but a vertical-axis field also takes line
/// breaks — the Return key inserts one, and a paste can carry them. A template is a
/// single line, so the editor feeds every edit through `adjusted(replacing:with:)`
/// and replays the stripped text, re-placing the caret from the returned offset.
public enum SingleLineText {

    /// Returns the edit from `old` to `new` with every line break removed, or `nil`
    /// when `new` holds none.
    ///
    /// When the edit is one contiguous insertion — a keystroke, a paste — the caret
    /// offset sits just past what was inserted, less the breaks dropped before it, so
    /// the caret stays where the user was typing. Any other edit (a programmatic
    /// replacement) leaves the caret at the end.
    public static func adjusted(replacing old: String, with new: String) -> BraceAutoClose.Adjustment? {
        let newChars = Array(new)
        guard newChars.contains(where: \.isNewline) else { return nil }
        let stripped = newChars.filter { !$0.isNewline }

        let oldChars = Array(old)
        var prefix = 0
        while prefix < oldChars.count && prefix < newChars.count && oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldChars.count - prefix && suffix < newChars.count - prefix
            && oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }
        guard newChars.count > oldChars.count, prefix + suffix == oldChars.count else {
            return BraceAutoClose.Adjustment(text: String(stripped), caretOffset: stripped.count)
        }

        let runEnd = newChars.count - suffix
        let droppedBeforeCaret = newChars[..<runEnd].filter(\.isNewline).count
        return BraceAutoClose.Adjustment(text: String(stripped), caretOffset: runEnd - droppedBeforeCaret)
    }

    /// Whether the edit from `old` to `new` is nothing but inserted line breaks — a
    /// Return keypress, which the editor reads as "done" and dismisses the keyboard.
    public static func isReturnKeypress(replacing old: String, with new: String) -> Bool {
        new.count > old.count && adjusted(replacing: old, with: new)?.text == old
    }
}
