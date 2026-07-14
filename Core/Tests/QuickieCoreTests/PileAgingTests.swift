import Foundation
import Testing
@testable import QuickieCore

// Pile aging cues (CONTEXT.md → Pile, aging paragraph; issue #164). Every entry
// wears its **age** — always shown, as the single coarsest unit ("3w ago") — in
// the muted subtitle channel, and the Pile page header carries the entry count
// plus the oldest-entry age. Presentation only: no expiry, no auto-delete. These
// tests pin the two pure pieces the app renders — the coarsest-unit age label and
// the header line — without reaching into SwiftUI.
struct PileAgingTests {

    // A fixed reference instant so the ladder is deterministic — no `Date()`.
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    @Test("the age label is a single coarsest unit, never a compound '3w 2d'")
    func labelIsCoarsestSingleUnit() {
        // One unit only: the largest that fits. 3 weeks + 2 days still reads "3w
        // ago" — the finer tail is dropped, matching the muted-subtitle style.
        #expect(RelativeAge.label(from: ago(23 * 86_400), asOf: now) == "3w ago")
    }

    @Test("the ladder climbs seconds → minutes → hours → days → weeks → months → years")
    func ladderClimbsThroughEveryUnit() {
        #expect(RelativeAge.label(from: ago(5), asOf: now) == "just now")   // < 1m
        #expect(RelativeAge.label(from: ago(90), asOf: now) == "1m ago")    // 1.5m
        #expect(RelativeAge.label(from: ago(2 * 3600), asOf: now) == "2h ago")
        #expect(RelativeAge.label(from: ago(4 * 86_400), asOf: now) == "4d ago")
        #expect(RelativeAge.label(from: ago(3 * 7 * 86_400), asOf: now) == "3w ago")
        #expect(RelativeAge.label(from: ago(60 * 86_400), asOf: now) == "2mo ago")
        #expect(RelativeAge.label(from: ago(800 * 86_400), asOf: now) == "2y ago")
    }

    @Test("each unit boundary rolls over cleanly at its exact threshold")
    func boundariesRollOverCleanly() {
        // Just under a minute is still "just now"; the 60s mark is the first "1m ago".
        #expect(RelativeAge.label(from: ago(59), asOf: now) == "just now")
        #expect(RelativeAge.label(from: ago(60), asOf: now) == "1m ago")
        #expect(RelativeAge.label(from: ago(3600), asOf: now) == "1h ago")
        #expect(RelativeAge.label(from: ago(86_400), asOf: now) == "1d ago")
        #expect(RelativeAge.label(from: ago(7 * 86_400), asOf: now) == "1w ago")
        // The last day of the fourth week still reads weeks; 30 days flips to months.
        #expect(RelativeAge.label(from: ago(29 * 86_400), asOf: now) == "4w ago")
        #expect(RelativeAge.label(from: ago(30 * 86_400), asOf: now) == "1mo ago")
        #expect(RelativeAge.label(from: ago(365 * 86_400), asOf: now) == "1y ago")
    }

    @Test("a just-created or clock-skewed entry never reads negative — it clamps to 'just now'")
    func nonPositiveAgeClampsToJustNow() {
        #expect(RelativeAge.label(from: now, asOf: now) == "just now")
        // A future createdAt (CloudKit clock skew) must not produce "-1m ago".
        #expect(RelativeAge.label(from: now.addingTimeInterval(500), asOf: now) == "just now")
    }

    @Test("the Pile page header shows the entry count and the oldest entry's age")
    func headerCarriesCountAndOldestAge() {
        let header = PileHeader.text(entryCount: 12, oldest: ago(3 * 7 * 86_400), asOf: now)
        #expect(header == "12 saved · oldest 3w ago")
    }

    @Test("an empty Pile shows no header at all — never '0 saved'")
    func emptyPileHasNoHeader() {
        #expect(PileHeader.text(entryCount: 0, oldest: nil, asOf: now) == nil)
        // Defensive: a zero count with a stray date still yields nothing.
        #expect(PileHeader.text(entryCount: 0, oldest: ago(10), asOf: now) == nil)
        // And a positive count with no oldest date (shouldn't happen) is also bare.
        #expect(PileHeader.text(entryCount: 3, oldest: nil, asOf: now) == nil)
    }

    @Test("a single-entry Pile still reads with the same 'N saved' shape")
    func singleEntryHeader() {
        #expect(PileHeader.text(entryCount: 1, oldest: ago(2 * 3600), asOf: now)
                == "1 saved · oldest 2h ago")
    }

    @Test("a Pile entry carries its age in the muted subtitle channel — the file-row anatomy")
    func pileEntryRowCarriesAgeSubtitle() {
        // The Result-list row reads the age off `subtitle`, the same optional-subtitle
        // channel a file row uses for its relative path — always shown, never opacity.
        let aged = Action.pileEntry(id: "pile.7", text: "book the campsite", age: "3w ago")
        #expect(aged.subtitle == "3w ago")
        // Age is presentation only: it changes nothing about the stage contract.
        #expect(aged.run() == .stagePileEntry(id: "pile.7"))
        // The command row that opens the page carries no age/count subtitle.
        #expect(Action.openPilePage().subtitle == nil)
    }
}
