import Foundation
import Testing
@testable import QuickieCore

// A Custom Action can wear a user-chosen SF Symbol as its leading glyph (CONTEXT.md
// → Custom Action; issue #163): picked from a curated, fuzzy-searchable set in the
// editor, it replaces the derived leading glyph on every surface. Unset, everything
// is identical to before (pure opt-in). These pin the pure Core seams — the glyph
// stamped onto the produced Action, and the curated catalog's fuzzy search.
struct CustomActionGlyphTests {

    // MARK: - The glyph flows onto the produced Action

    @Test("a chosen glyph is stamped onto a slotted Custom Action")
    func slottedActionCarriesGlyph() {
        let def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}",
            glyph: "checklist"
        )
        #expect(def.makeAction(id: "things")?.glyph == "checklist")
    }

    @Test("a chosen glyph is stamped onto a static (slot-less) Custom Action")
    func staticActionCarriesGlyph() {
        let def = CustomActionDefinition(
            name: "GitHub",
            template: "https://github.com",
            glyph: "globe"
        )
        let action = def.makeAction(id: "gh")
        #expect(action?.kind == .quicklink)
        #expect(action?.glyph == "globe")
    }

    @Test("no chosen glyph leaves the Action's glyph nil — the derived glyph applies")
    func unsetGlyphIsNil() {
        let slotted = CustomActionDefinition(name: "Search", template: "https://x.com/{q}")
        let staticLink = CustomActionDefinition(name: "Site", template: "https://x.com")
        #expect(slotted.makeAction(id: "a")?.glyph == nil)
        #expect(staticLink.makeAction(id: "b")?.glyph == nil)
    }

    @Test("a blank or whitespace-only glyph normalizes to nil, never a blank symbol")
    func blankGlyphNormalizesToNil() {
        // A synced-in or mis-set empty string must read as *unset* (derived glyph)
        // rather than render as an unrenderable blank leading symbol.
        let blank = CustomActionDefinition(name: "A", template: "https://x.com/{q}", glyph: "")
        let spaces = CustomActionDefinition(name: "B", template: "https://x.com", glyph: "   ")
        #expect(blank.makeAction(id: "a")?.glyph == nil)
        #expect(spaces.makeAction(id: "b")?.glyph == nil)
    }

    @Test("the trailing main-action glyph is untouched by a chosen leading glyph")
    func mainActionUnchanged() {
        // The leading glyph is user-set; the trailing one stays derived from the
        // outcome, so it can't drift from behavior (issue #163 acceptance).
        let def = CustomActionDefinition(name: "Site", template: "https://x.com", glyph: "star")
        #expect(def.makeAction(id: "a")?.mainAction == .openInBrowser)
    }

    // MARK: - The curated catalog's fuzzy search

    @Test("an empty query returns the whole curated set in display order")
    func emptyQueryReturnsAll() {
        #expect(CustomActionGlyphCatalog.search("") == CustomActionGlyphCatalog.all)
        #expect(CustomActionGlyphCatalog.search("   ") == CustomActionGlyphCatalog.all)
    }

    @Test("search matches a symbol by its label")
    func matchesByLabel() {
        let results = CustomActionGlyphCatalog.search("calendar")
        #expect(results.first?.name == "calendar")
    }

    @Test("search finds a symbol by an intent keyword, not just its name")
    func matchesByKeyword() {
        // "email" isn't in the symbol name `envelope` — the keyword bridges intent.
        let results = CustomActionGlyphCatalog.search("email")
        #expect(results.contains { $0.name == "envelope" })
    }

    @Test("search finds a symbol by its exact SF Symbol name")
    func matchesBySymbolName() {
        let results = CustomActionGlyphCatalog.search("magnifyingglass")
        #expect(results.first?.name == "magnifyingglass")
    }

    @Test("a query nothing matches returns no options")
    func noMatchReturnsEmpty() {
        #expect(CustomActionGlyphCatalog.search("zzzqxwv").isEmpty)
    }

    @Test("every curated symbol has a unique name")
    func namesAreUnique() {
        let names = CustomActionGlyphCatalog.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    // MARK: - Shared shape→kind and normalization helpers

    @Test("derivedKind is a Custom Action when slotted, a static link when not")
    func derivedKindFollowsShape() {
        let slotted = CustomActionDefinition(name: "S", template: "https://x.com/{q}")
        let staticLink = CustomActionDefinition(name: "L", template: "https://x.com")
        #expect(slotted.derivedKind == .customAction)
        #expect(staticLink.derivedKind == .quicklink)
        // The static helper (for a surface holding only the raw template) agrees.
        #expect(CustomActionDefinition.derivedKind(forTemplate: "https://x.com/{q}") == .customAction)
        #expect(CustomActionDefinition.derivedKind(forTemplate: "https://x.com") == .quicklink)
    }

    @Test("normalizedGlyph collapses blank and whitespace to nil, keeps a real name")
    func normalizedGlyphRule() {
        #expect(CustomActionDefinition.normalizedGlyph(nil) == nil)
        #expect(CustomActionDefinition.normalizedGlyph("") == nil)
        #expect(CustomActionDefinition.normalizedGlyph("   ") == nil)
        #expect(CustomActionDefinition.normalizedGlyph("star") == "star")
    }
}
