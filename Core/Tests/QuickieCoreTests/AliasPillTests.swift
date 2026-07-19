import Foundation
import Testing
@testable import QuickieCore

// The Alias pill (CONTEXT.md → Alias pill; issue #196): a Custom Action (or a
// Shortcut with an alias) always wears its user-authored alias as a dim capsule
// after the title, query or not. Bolding layers on top via the single-source
// rule — when the alias strictly outscored the title, the pill's matched letters
// bold and the title stays plain; otherwise the title bolds and the pill stays
// dim. These tests pin the per-Action `aliasPill` carve-outs and the engine's
// `aliasBold` spans.
struct AliasPillTests {

    // MARK: - Which Actions carry a pill

    @Test("a static Custom Action shows its alias as a pill")
    func staticCustomActionShowsPill() {
        let action = Action.quicklink(
            id: "gh", title: "GitHub", aliases: ["gh"],
            url: URL(string: "https://github.com")!
        )
        #expect(action.aliasPill == "gh")
    }

    @Test("a slotted Custom Action shows its alias as a pill")
    func slottedCustomActionShowsPill() {
        let action = CustomActionDefinition(
            name: "Things", aliases: ["th"], template: "things:///add?title={title}"
        ).makeAction(id: "things")
        #expect(action?.aliasPill == "th")
    }

    @Test("an alias-less Custom Action shows no pill")
    func aliaslessCustomActionShowsNoPill() {
        let action = Action.quicklink(
            id: "ex", title: "Example", url: URL(string: "https://example.com")!
        )
        #expect(action.aliasPill == nil)
    }

    @Test("a built-in command row never shows a pill despite its aliases")
    func builtinCommandShowsNoPill() {
        // The Computed command carries "calc", "converter" as matching fodder — never
        // a name to re-teach.
        #expect(Action.openCalculatorPage().aliasPill == nil)
        #expect(Action.openSettings().aliasPill == nil)
        #expect(Action.searchFiles().aliasPill == nil)
        // The built-in captures carry aliases too, and still show none.
        #expect(Action.saveForLater().aliasPill == nil)
        #expect(Action.newSnippet().aliasPill == nil)
    }

    @Test("a Pile entry never shows a pill though its body rides as an alias")
    func pileEntryShowsNoPill() {
        let entry = Action.pileEntry(id: "p", text: "remember the oatmilk")
        #expect(!entry.aliases.isEmpty)  // the body *is* the alias
        #expect(entry.aliasPill == nil)  // but it is not a user-defined name
    }

    @Test("a Shortcut pills only when it carries an alias")
    func shortcutPillsOnlyWithAlias() {
        // Shortcuts have no aliases today, so no pill — future-proofed by kind.
        #expect(Action.shortcut(name: "Log Water").aliasPill == nil)
    }

    // MARK: - Bolding via the single-source rule (engine-produced spans)

    private func engine(catalog: [Action]) -> SearchEngine {
        SearchEngine(providers: [IndexedProvider(catalog: catalog)])
    }

    @Test("when the alias strictly outscores the title, the pill bolds and the title stays plain")
    func aliasWinnerBoldsPillNotTitle() {
        // Title "Open GitHub" only *contains* "gh" buried; the alias "gh" is an exact
        // match, so it wins — the title bolds nothing and the pill bolds both letters.
        let engine = engine(catalog: [
            .quicklink(id: "gh", title: "Open GitHub", aliases: ["gh"], url: URL(string: "https://github.com")!)
        ])
        let row = engine.rows(for: "gh").first { $0.action.id == "gh" }
        #expect(row?.match?.winningCandidate == .alias(0))
        #expect(row?.match?.titleBold == [])
        #expect(row?.match?.aliasBold == [0, 1])
    }

    @Test("when the title wins, the pill stays dim (no alias bold)")
    func titleWinnerLeavesPillDim() {
        // "git" prefixes the title "GitHub" (strong) and the alias "gh" only weakly
        // matches; the title wins, so the title bolds and the pill carries no bold.
        let engine = engine(catalog: [
            .quicklink(id: "gh", title: "GitHub", aliases: ["gh"], url: URL(string: "https://github.com")!)
        ])
        let row = engine.rows(for: "git").first { $0.action.id == "gh" }
        #expect(row?.match?.winningCandidate == .title)
        #expect(row?.match?.titleBold == [0, 1, 2])
        #expect(row?.match?.aliasBold == [])
    }

    @Test("pillBold gates the alias spans on the shown pill being the winner")
    func pillBoldGatesOnPillIdentity() {
        // Winner is the alias "gh": pillBold returns its spans for the pill "gh"…
        let aliasWon = MatchHighlight(winningCandidate: .alias(0), titleBold: [], aliasBold: [0, 1])
        #expect(aliasWon.pillBold(for: "gh", aliases: ["gh"]) == [0, 1])
        // …but not for a different pill string, and not for an out-of-range index.
        #expect(aliasWon.pillBold(for: "other", aliases: ["gh"]) == [])
        #expect(aliasWon.pillBold(for: "gh", aliases: []) == [])
        // Title won: the pill stays dim whatever it shows (single-source rule).
        let titleWon = MatchHighlight(winningCandidate: .title, titleBold: [0, 1, 2], aliasBold: [])
        #expect(titleWon.pillBold(for: "gh", aliases: ["gh"]) == [])
    }

    @Test("a fallback-region row carries no match, so its pill can never bold")
    func fallbackRowPillNeverBolds() {
        // A text-first Custom Action activated as a fallback rides the bottom region
        // with `match == nil` — the pill still shows (via `aliasPill`) but has no
        // spans to bold from.
        let fallback = CustomActionDefinition(
            name: "Web Search", aliases: ["search"], template: "https://example.com/?q={q}"
        ).makeAction(id: "web")!
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: [fallback])],
            enabledFallbacks: ["web"]
        )
        let row = engine.rows(for: "search").first { $0.region == .fallback }
        #expect(row != nil)
        #expect(row?.match == nil)
        #expect(row?.action.aliasPill == "search")
    }
}
