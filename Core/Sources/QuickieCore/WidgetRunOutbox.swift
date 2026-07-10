import Foundation

/// One widget-run selection pending its Frecency credit (ADR 0025; issue #126):
/// which Action ran, and when. The timestamp is the run's real moment — recorded
/// when the widget intent fired, not when the app later drains it — so Frecency's
/// recency decay sees the truth even if the app stays backgrounded for days.
public struct WidgetRunEvent: Equatable, Sendable, Codable {
    public let actionID: String
    public let date: Date

    public init(actionID: String, date: Date) {
        self.actionID = actionID
        self.date = date
    }
}

/// The Favorites widget's **frecency outbox** (ADR 0025; issue #126). A widget-run
/// selection counts toward Frecency — the actions run most from the widget are
/// precisely the user's most-favored — but `SignalsStore` loads once at app launch
/// and rewrites keys whole, so a direct cross-process write would be clobbered by
/// the app's next save. The widget intent instead appends `(actionId, timestamp)`
/// to a pending-events App Group key; the app drains the outbox into `SignalsStore`
/// on foreground. Frecency stays **single-writer** — the widget never touches
/// `SignalsStore` keys.
///
/// Only the copy and hand-off lanes append here: an `openApp` run lands in the app,
/// where the ordinary tap path records its own frecency event — outboxing it too
/// would double-count.
///
/// The append/decode logic is pure Core so the merge is `swift test`-covered;
/// reads are tolerant (absent or garbage data is an empty outbox) so a corrupt key
/// can never wedge the widget or the drain.
public enum WidgetRunOutbox {
    /// The most pending events the outbox holds — appends beyond it drop the
    /// oldest. A safety valve, not a working limit: the outbox drains on every app
    /// foreground, so reaching the cap means the app hasn't opened across hundreds
    /// of widget runs, and the freshest events are the ones worth crediting.
    public static let capacity = 200

    /// The pending events in arrival order, or `[]` when the key is absent, empty,
    /// or unreadable — the drain never fails, it just has nothing to credit.
    public static func events(from data: Data?) -> [WidgetRunEvent] {
        guard let data,
              let decoded = try? JSONDecoder().decode([WidgetRunEvent].self, from: data)
        else { return [] }
        return decoded
    }

    /// The outbox with `event` appended (oldest dropped past `capacity`), as the
    /// blob to write back. Unreadable existing data is treated as empty rather
    /// than propagated, so one corrupt write can't poison every later append.
    public static func appending(_ event: WidgetRunEvent, to data: Data?) -> Data {
        var events = events(from: data)
        events.append(event)
        let capped = Array(events.suffix(capacity))
        // Encoding a value of plain Codable structs can't realistically fail; the
        // fallback only keeps the signature total without an untestable throw.
        return (try? JSONEncoder().encode(capped)) ?? (data ?? Data())
    }
}
