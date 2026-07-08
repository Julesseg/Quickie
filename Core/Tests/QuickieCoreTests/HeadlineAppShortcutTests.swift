import Foundation
import Testing
@testable import QuickieCore

// `HeadlineAppShortcut` is the Core-owned, `swift test`-covered description of the
// four headline App Shortcuts (issue #121; ADR 0024) — the split invoke shapes and
// the `quickie://` route each foreground one opens. The App target's App Intents are
// a thin shell over it: keeping the routes and the write rule here is what stops the
// intents' targets from drifting off the built-in ids they steer (the same "can never
// drift" rationale as `Action.saveForLaterID`).
struct HeadlineAppShortcutTests {

    // MARK: Foreground routes

    @Test("Quick Capture opens the fresh-entry reset")
    func quickCaptureRidesEntry() {
        #expect(HeadlineAppShortcut.quickCapture.deeplink == .entry)
    }

    @Test("New Reminder rides run/builtin.new-reminder, not a capture door")
    func newReminderRidesRun() {
        #expect(HeadlineAppShortcut.newReminder.deeplink == .run(id: Action.newReminderID))
    }

    @Test("New Event rides run/builtin.new-event, not a capture door")
    func newEventRidesRun() {
        #expect(HeadlineAppShortcut.newEvent.deeplink == .run(id: Action.newEventID))
    }

    @Test("the capture routes steer the live built-in capture command rows")
    func captureRoutesMatchTheBuiltInIDs() {
        // The route's id must be the exact id the factory indexes the capture under,
        // or the deeplink would open plain Home instead of the capture (ADR 0024).
        #expect(Action.newReminder().id == Action.newReminderID)
        #expect(Action.newEvent().id == Action.newEventID)
    }

    // MARK: Split invoke shapes

    @Test("Save for later is the only background verb; it opens no deeplink")
    func saveForLaterIsBackground() {
        #expect(HeadlineAppShortcut.saveForLater.deeplink == nil)
        #expect(HeadlineAppShortcut.saveForLater.runsInBackground)
    }

    @Test("the three capture/entry verbs run in the foreground")
    func foregroundVerbsSteerTheApp() {
        for shortcut in [HeadlineAppShortcut.quickCapture, .newReminder, .newEvent] {
            #expect(!shortcut.runsInBackground)
            #expect(shortcut.deeplink != nil)
        }
    }

    // MARK: Deeplink URL round-trips through slice-1's grammar

    @Test("each foreground verb's URL round-trips back to its route")
    func foregroundURLsRoundTrip() throws {
        for shortcut in [HeadlineAppShortcut.quickCapture, .newReminder, .newEvent] {
            let url = try #require(shortcut.deeplinkURL)
            #expect(QuickieDeeplink.parse(url) == shortcut.deeplink)
        }
    }

    @Test("the background verb has no URL to open")
    func backgroundVerbHasNoURL() {
        #expect(HeadlineAppShortcut.saveForLater.deeplinkURL == nil)
    }

    // MARK: Save for later write rule

    @Test("dictated text is trimmed to the Pile entry that gets written")
    func dictatedTextIsTrimmed() {
        #expect(HeadlineAppShortcut.pileText(fromDictated: "  buy milk  ") == "buy milk")
    }

    @Test("non-empty dictation is written verbatim after trimming")
    func nonEmptyDictationIsWritten() {
        #expect(HeadlineAppShortcut.pileText(fromDictated: "call the vet") == "call the vet")
    }

    @Test("empty or whitespace-only dictation writes nothing (Siri re-prompts)")
    func emptyDictationWritesNothing() {
        #expect(HeadlineAppShortcut.pileText(fromDictated: "") == nil)
        #expect(HeadlineAppShortcut.pileText(fromDictated: "   \n\t ") == nil)
    }
}
