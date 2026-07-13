#if canImport(ActivityKit)
import ActivityKit

/// The Live Activity behind a **Pending query** (issue #152): while the
/// 30-second window is open, the unfinished query is glanceable on the Lock
/// Screen / Dynamic Island and tappable to hop straight back to it. Shared by
/// the two processes that touch it — the app requests and ends the activity,
/// the widget extension renders it — which is why it lives in the folder
/// synced into both targets, like `DeeplinkInbox`.
///
/// The preview rides `ContentState` (fixed for the activity's life — the
/// activity *is* the visible lifetime of one pending query, so there is
/// nothing to update). The compact and minimal Dynamic Island presentations
/// deliberately never render it: generic glyphs only there; the truncated text
/// belongs to the expanded and Lock Screen presentations alone.
struct PendingQueryActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The pending query's text, shown truncated with a return-arrow glyph
        /// expressing "return to it".
        var preview: String
    }
}
#endif
