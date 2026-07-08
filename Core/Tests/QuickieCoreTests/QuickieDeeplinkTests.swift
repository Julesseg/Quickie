import Foundation
import Testing
@testable import QuickieCore

// `QuickieDeeplink` is the pure parse/build half of the `quickie://` inbound
// door the App Intents bridge and epic #16's entry surfaces ride (issue #120;
// ADR 0024) — a sibling to `ShortcutImport` (Sync-Shortcut ingest) and
// `ShortcutRun` (the run round-trip) on the same scheme. These tests pin the
// grammar the app dispatches on: the four routes it recognizes, the junk it
// ignores, and the round-trip through the outbound builders the later bridge
// slices construct their URLs with.
struct QuickieDeeplinkTests {

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: Capture routes

    @Test("capture/reminder parses to the Reminder capture route")
    func captureReminder() {
        #expect(QuickieDeeplink.parse(url("quickie://capture/reminder")) == .captureReminder)
    }

    @Test("capture/event parses to the Event capture route")
    func captureEvent() {
        #expect(QuickieDeeplink.parse(url("quickie://capture/event")) == .captureEvent)
    }

    @Test("an unknown capture leaf is ignored")
    func unknownCaptureLeafIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://capture/note")) == nil)
    }

    @Test("a bare capture host with no leaf is ignored")
    func bareCaptureIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://capture")) == nil)
    }

    // MARK: Run route

    @Test("run/<id> parses to a tap-equivalent run carrying the id")
    func runCarriesID() {
        #expect(QuickieDeeplink.parse(url("quickie://run/seed.web-search")) == .run(id: "seed.web-search"))
    }

    @Test("a run id's percent-encoding is decoded")
    func runIDDecoded() {
        #expect(QuickieDeeplink.parse(url("quickie://run/my%20link")) == .run(id: "my link"))
    }

    @Test("a bare run host with no id is ignored")
    func bareRunIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://run")) == nil)
        #expect(QuickieDeeplink.parse(url("quickie://run/")) == nil)
    }

    // MARK: Entry route

    @Test("entry parses to the fresh-entry reset")
    func entry() {
        #expect(QuickieDeeplink.parse(url("quickie://entry")) == .entry)
    }

    @Test("entry with a trailing path is ignored, not a silent reset")
    func entryWithPathIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://entry/extra")) == nil)
    }

    // MARK: Non-deeplink URLs are ignored

    @Test("a foreign scheme is ignored")
    func foreignSchemeIgnored() {
        #expect(QuickieDeeplink.parse(url("shortcuts://run/thing")) == nil)
    }

    @Test("the sibling import route is not a deeplink")
    func importRouteIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://import?names=a")) == nil)
    }

    @Test("the sibling shortcut-result route is not a deeplink")
    func shortcutResultIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://shortcut-result?result=x")) == nil)
    }

    @Test("an unknown host is ignored")
    func unknownHostIgnored() {
        #expect(QuickieDeeplink.parse(url("quickie://frobnicate")) == nil)
    }

    // MARK: Round-trip through the outbound builders

    @Test("the entry builder round-trips to the entry route")
    func entryBuilderRoundTrips() {
        #expect(QuickieDeeplink.parse(QuickieDeeplink.entryURL()) == .entry)
    }

    @Test("the capture builders round-trip to their routes")
    func captureBuildersRoundTrip() {
        #expect(QuickieDeeplink.parse(QuickieDeeplink.captureReminderURL()) == .captureReminder)
        #expect(QuickieDeeplink.parse(QuickieDeeplink.captureEventURL()) == .captureEvent)
    }

    @Test("the run builder round-trips an id with reserved characters")
    func runBuilderRoundTripsReservedID() {
        let id = "custom action/with space"
        #expect(QuickieDeeplink.parse(QuickieDeeplink.runURL(id: id)) == .run(id: id))
    }
}
