import Foundation
import Testing
@testable import QuickieCore

// The Pile is the collection of raw query texts the user saved to deal with
// later (CONTEXT.md → Pile; ADR 0018) — replacing the Note system wholesale. A
// Pile entry is just a block of text: no title, no reader, no compose-editor.
// Its main action **stages** the text (CONTEXT.md → Stage): the app replaces
// the input query with the entry's saved text, re-runs the matcher, and the
// entry leaves the Pile — the same reinjection move as a Shortcut Action's
// returned output. These tests pin the stage contract, the silent "Save for
// later" capture, and body-text search without reaching into how the Pile is
// stored.
struct PileTests {

    @Test("a Pile entry's main action stages it — the outcome carries its identity for the app to resolve, reinject, and consume")
    func pileEntryStages() {
        let entry = Action.pileEntry(id: "pile.42", text: "compare ferry vs train to Nanaimo")
        #expect(entry.run() == .stagePileEntry(id: "pile.42"))
    }

    @Test("a Pile entry declares its text content by id, so it offers copy + share")
    func pileEntryContentIsItsText() {
        // The entry's Result content is an edge-resolved reference (CONTEXT.md →
        // Result content): its text by id, dereferenced by the app on demand —
        // the reference "Remove from Pile" will also key off when the long-press
        // slice lands.
        let entry = Action.pileEntry(id: "pile.7", text: "book the campsite")
        #expect(entry.content == .pileEntry(id: "pile.7"))
        #expect(secondaryActions(for: entry.content) == [.copy, .share])
    }

    @Test("a Pile entry's row reads as a stage: its own main action, Enter labelled .go")
    func pileEntryPresentsAsStage() {
        let entry = Action.pileEntry(id: "pile.9", text: "renew the passport")
        // Staging is neither an open nor a copy — the trailing glyph must say
        // "this text goes back into the input", so it classifies as its own case.
        #expect(entry.mainAction == .stage)
        // Enter on the highlighted Pile row stages it — the Return key reads Go.
        #expect(entry.returnKeyLabel == .go)
    }

    @Test("a Pile entry is fuzzy-matched over its body text and stages from its result row")
    func pileEntryIsSearchableByBodyText() {
        // There is no title to match — the body text is the entry's whole name
        // in the index, so a forgiving subsequence over any part of it surfaces
        // the entry as a normal ranked row.
        let pile = IndexedProvider(catalog: [
            .pileEntry(id: "pile.ferry", text: "compare ferry vs train to Nanaimo"),
            .pileEntry(id: "pile.dentist", text: "call the dentist about the crown"),
        ])
        let engine = SearchEngine(providers: [pile])

        let results = engine.results(for: "ferry")
        #expect(results.map(\.id) == ["pile.ferry"])
        // Staging works from the result row: the same stage outcome as anywhere.
        #expect(results.first?.run() == .stagePileEntry(id: "pile.ferry"))
    }

    @Test("the Save for later Fallback captures the typed text silently — no editor, no confirm")
    func saveForLaterCapturesSilently() {
        let capture = Action.saveForLater()
        // A Fallback (CONTEXT.md → Fallback Action): always surfaced, consuming
        // the raw typed text. Running it drops the text straight into the Pile —
        // a silent save outcome the app performs, not a seeded editor.
        #expect(capture.isFallback)
        #expect(capture.inputTypes == [.text])
        #expect(capture.run(input: "look into e-bike rebates")
                == .saveToPile(text: "look into e-bike rebates"))
        // Silent capture, like a copy-out: the Return key reads Done.
        #expect(capture.returnKeyLabel == .done)
    }

    // An engine wired like the app: saved Pile entries feeding the index plus
    // the always-present "Save for later" capture and the web-search Fallback.
    private func engine() -> SearchEngine {
        SearchEngine(providers: [
            IndexedProvider(catalog: [
                .pileEntry(id: "pile.ferry", text: "compare ferry vs train to Nanaimo"),
                .pileEntry(id: "pile.dentist", text: "call the dentist about the crown"),
            ]),
            IndexedProvider(catalog: [.saveForLater(), .webSearchFallback()]),
        ])
    }

    @Test("Save for later rides the bottom region below body-matched Pile entries")
    func saveForLaterPinnedBelowMatches() {
        // "ferry" body-matches an entry; the capture still rides along, pinned
        // in the bottom fallback region with web-search — never above the match.
        let ids = engine().results(for: "ferry").map(\.id)
        #expect(ids.first == "pile.ferry")
        #expect(ids.contains("builtin.save-for-later"))
        #expect(ids.firstIndex(of: "builtin.save-for-later")! > ids.firstIndex(of: "pile.ferry")!)
    }

    @Test("Save for later is present even when nothing matches by name")
    func saveForLaterAppearsForNonMatchingQuery() {
        // A brand-new thought matches nothing; only the Fallbacks serve it, so a
        // query can always be deferred into the Pile.
        let ids = engine().results(for: "buy a birthday gift for mum").map(\.id)
        #expect(ids.contains("builtin.save-for-later"))
    }

    @Test("an empty query surfaces no capture (Home state)")
    func emptyQueryHasNoCapture() {
        #expect(engine().results(for: "").isEmpty)
        #expect(engine().results(for: "   ").isEmpty)
    }

    @Test("the Pile command row opens the full-screen Pile page, by name or alias")
    func pileCommandOpensPilePage() {
        let command = Action.openPilePage()
        #expect(command.run() == .openPage(.pile))
        // A command, not a Fallback — it matches by name (pile / later / saved)
        // and doesn't ride the bottom region.
        #expect(command.isFallback == false)

        let engine = SearchEngine(providers: [IndexedProvider(catalog: [command])])
        for query in ["pile", "later", "saved"] {
            #expect(engine.results(for: query).map(\.id) == [command.id],
                    "the Pile page should surface for \(query)")
        }
    }
}
