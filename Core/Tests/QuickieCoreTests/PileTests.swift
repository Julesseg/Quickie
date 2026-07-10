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
        #expect(secondaryActions(for: entry.content) == [.copy, .share, .copyDeeplink])
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

    @Test("a Pile entry's row title is a single line, capped — the raw text can be a multi-line blob")
    func pileEntryTitleIsSingleLineAndCapped() {
        // The saved text is whatever was typed — possibly a large multi-line
        // paste. The row must still read as the same one-line pill as every
        // other result, so the display title is the first non-empty line,
        // length-capped; the full text stays the matching surface (below).
        let multiline = Action.pileEntry(
            id: "pile.trip",
            text: "Trip planning\ncompare ferry vs train to Nanaimo\nbook the campsite"
        )
        #expect(multiline.title == "Trip planning")

        let long = Action.pileEntry(id: "pile.long", text: String(repeating: "a", count: 200))
        #expect(long.title.count == 60)
    }

    @Test("a multi-line Pile entry still matches over its whole body text, not just the shown line")
    func multiLinePileEntryMatchesBeyondItsTitle() {
        let pile = IndexedProvider(catalog: [
            .pileEntry(id: "pile.trip", text: "Trip planning\ncompare ferry vs train to Nanaimo"),
        ])
        let engine = SearchEngine(providers: [pile])
        // "ferry" lives on the second line — invisible in the row title, but the
        // body is the entry's whole name in the index (CONTEXT.md → Pile).
        #expect(engine.results(for: "ferry").map(\.id) == ["pile.trip"])
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
        // Fallback-eligible by kind (CONTEXT.md → Fallback Action): a permanent
        // built-in capture that consumes the raw typed text. Running it drops the
        // text straight into the Pile — a silent save outcome the app performs, not
        // a seeded editor.
        #expect(capture.isFallbackEligible)
        #expect(capture.inputTypes == [.text])
        #expect(capture.run(input: "look into e-bike rebates")
                == .saveToPile(text: "look into e-bike rebates"))
        // Silent capture, like a copy-out: the Return key reads Done.
        #expect(capture.returnKeyLabel == .done)
    }

    // An engine wired like the app: saved Pile entries feeding the index plus
    // the always-present "Save for later" capture and the web-search Fallback.
    private func engine() -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    .pileEntry(id: "pile.ferry", text: "compare ferry vs train to Nanaimo"),
                    .pileEntry(id: "pile.dentist", text: "call the dentist about the crown"),
                ]),
                IndexedProvider(catalog: [.saveForLater(), .webSearchFallback()]),
            ],
            enabledFallbacks: [Action.saveForLaterID, Action.webSearchFallbackID]
        )
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

    @Test("a Pile entry is not favorite-eligible — staging consumes it, so a pin would ghost a grid slot")
    func pileEntryIsNotFavoriteEligible() {
        // A Pile entry's main action removes it from the Pile (CONTEXT.md →
        // Stage), so a pinned one would outlive its target the first time it is
        // used — invisible on the grid, yet still holding one of the four slots.
        // It is therefore never pinnable; the App omits its Pin item off this.
        let entry = Action.pileEntry(id: "pile.ferry", text: "compare ferry vs train to Nanaimo")
        #expect(entry.isFavoriteEligible == false)
        // A query-only capture (Save for later, New Snippet) is likewise not pinnable
        // (issue #140): pinned, its card would run with no query and do nothing — a
        // dead card. It stays a Fallback, just not a standalone pin.
        #expect(Action.saveForLater().isFavoriteEligible == false)
        #expect(Action.newSnippet().isFavoriteEligible == false)
        // Durable, standalone-runnable catalog members stay pinnable: a command row
        // (opens its page) and a text-first Custom Action fallback (launches verb-first).
        #expect(Action.openPilePage().isFavoriteEligible)
        #expect(Action.webSearchFallback().isFavoriteEligible)
    }

    @Test("resolvableHomeIDs excludes Pile entries, so a stale Pile pin is pruned at reconciliation")
    func resolvableHomeIDsExcludesPileEntries() {
        // The App reconciles persisted Favorites against this set at launch. A
        // pin an older build allowed on a Pile entry must drop out — even while
        // the entry still exists — or it ghosts a Favorites slot the moment the
        // entry is staged (consumed).
        let ids = engine().resolvableHomeIDs()
        #expect(!ids.contains("pile.ferry"))
        #expect(!ids.contains("pile.dentist"))
        // A query-only capture is pruned here too (issue #140): like a Pile entry it
        // is not favorite-eligible, so a pin an older build allowed on Save for later
        // drops out at reconciliation.
        #expect(!ids.contains(Action.saveForLaterID))
        // A standalone-runnable pin keeps resolving, so real pins survive.
        #expect(ids.contains(Action.webSearchFallbackID))
    }

    @Test("the Pile command row opens the entries page — content, not the provider's settings")
    func pileCommandOpensPilePage() {
        // The entries are temporary: their page is purely content to view and
        // act on (tap stages, swipe discards), so the typed row opens its own
        // `.pile` destination — NOT the Pile provider's settings page, which is
        // reached from the Settings hub's Providers list instead.
        let command = Action.openPilePage()
        #expect(command.run() == .openPage(.pile))
        #expect(command.run() != .openPage(.settings(panel: .pile)))
        // A command, not a Fallback — it matches by name (pile / later / saved)
        // and isn't fallback-eligible, so it never rides the bottom region.
        #expect(command.isFallbackEligible == false)

        let engine = SearchEngine(providers: [IndexedProvider(catalog: [command])])
        for query in ["pile", "later", "saved"] {
            #expect(engine.results(for: query).map(\.id) == [command.id],
                    "the Pile page should surface for \(query)")
        }
    }
}
