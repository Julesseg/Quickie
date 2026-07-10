import Foundation
import Testing
@testable import QuickieCore

// The Favorites widget's **frecency outbox** (ADR 0025; issue #126): a widget-run
// selection counts toward Frecency, but `SignalsStore` loads once at app launch and
// rewrites keys whole, so a direct cross-process write would be clobbered by the
// app's next save. The widget intent instead appends `(actionId, timestamp)` to a
// pending-events App Group key; the app drains the outbox into `SignalsStore` on
// foreground. The append/merge/decode logic is pure `QuickieCore`, covered here so
// Frecency stays single-writer without a device in the loop.
struct WidgetRunOutboxTests {

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("an empty or absent outbox decodes to no events")
    func emptyOutboxHasNoEvents() {
        #expect(WidgetRunOutbox.events(from: nil) == [])
        #expect(WidgetRunOutbox.events(from: Data()) == [])
    }

    @Test("appending to an empty outbox records the one event")
    func appendToEmpty() {
        let event = WidgetRunEvent(actionID: "ql.docs", date: noon)
        let data = WidgetRunOutbox.appending(event, to: nil)
        #expect(WidgetRunOutbox.events(from: data) == [event])
    }

    @Test("appends accumulate in arrival order — the app drains them as they happened")
    func appendsAccumulateInOrder() {
        let first = WidgetRunEvent(actionID: "ql.docs", date: noon)
        let second = WidgetRunEvent(actionID: "snippet.a", date: noon.addingTimeInterval(60))
        let third = WidgetRunEvent(actionID: "ql.docs", date: noon.addingTimeInterval(120))
        var data = WidgetRunOutbox.appending(first, to: nil)
        data = WidgetRunOutbox.appending(second, to: data)
        data = WidgetRunOutbox.appending(third, to: data)
        #expect(WidgetRunOutbox.events(from: data) == [first, second, third])
    }

    @Test("an event's timestamp survives the round trip — frecency decay needs the real moment")
    func timestampSurvives() {
        let event = WidgetRunEvent(actionID: "ql.docs", date: noon)
        let drained = WidgetRunOutbox.events(from: WidgetRunOutbox.appending(event, to: nil))
        #expect(drained.first?.date == noon)
    }

    @Test("garbage in the key is treated as empty — an append still lands its event")
    func garbageDegradesToEmpty() {
        let garbage = Data("not json".utf8)
        #expect(WidgetRunOutbox.events(from: garbage) == [])
        let event = WidgetRunEvent(actionID: "ql.docs", date: noon)
        #expect(WidgetRunOutbox.events(from: WidgetRunOutbox.appending(event, to: garbage)) == [event])
    }

    @Test("the outbox is capped, dropping the oldest — it can't grow without bound if the app never foregrounds")
    func outboxCapsDroppingOldest() {
        var data: Data? = nil
        for index in 0...(WidgetRunOutbox.capacity) {
            data = WidgetRunOutbox.appending(
                WidgetRunEvent(actionID: "action.\(index)", date: noon.addingTimeInterval(Double(index))),
                to: data
            )
        }
        let events = WidgetRunOutbox.events(from: data)
        #expect(events.count == WidgetRunOutbox.capacity)
        // The newest events survive; the oldest was dropped.
        #expect(events.first?.actionID == "action.1")
        #expect(events.last?.actionID == "action.\(WidgetRunOutbox.capacity)")
    }
}
