import Foundation
import Testing
@testable import QuickieCore

// The built-in Catalog and the four default seeds (CONTEXT.md → Catalog; ADR
// 0028; issue #143). The acceptance criteria demand every shipped template be
// validated by `swift test` — parses, ≥ 1 slot, schemed — with unverifiable
// templates dropped from the data rather than shipped broken. These pin that gate,
// so a template that can't produce a working Custom Action fails the suite.
struct CatalogTests {

    // MARK: - Every shipped template is valid

    @Test("every catalog entry's template parses and is schemed; only Sites entries are slot-less")
    func everyEntryIsValid() {
        for entry in Catalog.entries {
            let def = entry.definition
            #expect(def.urlIsSchemedAfterProbe, "\(entry.name) is not schemed")
            #expect(def.isValidForSave, "\(entry.name) fails the Save gates")
            #expect(def.makeAction(id: entry.id) != nil, "\(entry.name) factories no Action")
            // A Sites entry is a static (slot-less) link; every other section is
            // templated and must carry at least one slot (ADR 0030).
            if entry.category == .sites {
                #expect(!def.hasSlot, "\(entry.name) is a Site but carries a {slot}")
            } else {
                #expect(def.hasSlot, "\(entry.name) has no {slot}")
            }
        }
    }

    // MARK: - Default glyphs (every entry ships a best-match curated symbol)

    @Test("every catalog entry carries a default glyph from the curated glyph catalog")
    func everyEntryCarriesACuratedGlyph() {
        // The curated set is what the editor's picker offers — a glyph outside it
        // would render fine but be unreachable to re-pick after clearing, and could
        // even be a typo'd, unrenderable symbol name. Membership pins both.
        let curated = Set(CustomActionGlyphCatalog.all.map(\.name))
        for entry in Catalog.entries {
            let glyph = CustomActionDefinition.normalizedGlyph(entry.glyph)
            #expect(glyph != nil, "\(entry.name) ships no default glyph")
            if let glyph {
                #expect(curated.contains(glyph), "\(entry.name)'s glyph '\(glyph)' is not in the curated catalog")
            }
        }
    }

    @Test("an entry's default glyph flows into the definition an install persists")
    func glyphFlowsIntoInstalledDefinition() {
        // Install persists `entry.definition` verbatim, and `makeAction` stamps the
        // glyph onto the produced Action — so the row's badge, the installed action,
        // and every result surface agree.
        for entry in Catalog.entries {
            #expect(entry.definition.glyph == entry.glyph, "\(entry.name)'s definition drops its glyph")
            #expect(entry.definition.makeAction(id: entry.id)?.glyph == entry.glyph,
                    "\(entry.name)'s Action does not wear its default glyph")
        }
    }

    @Test("every default seed carries a curated default glyph")
    func everySeedCarriesACuratedGlyph() {
        let curated = Set(CustomActionGlyphCatalog.all.map(\.name))
        for seed in CatalogSeed.all {
            let glyph = seed.definition.normalizedGlyph
            #expect(glyph != nil, "\(seed.id) ships no default glyph")
            if let glyph {
                #expect(curated.contains(glyph), "\(seed.id)'s glyph '\(glyph)' is not in the curated catalog")
            }
        }
    }

    @Test("catalog entry ids are unique")
    func entryIDsAreUnique() {
        let ids = Catalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("every category is represented and entries are grouped in shipped order")
    func categoriesArePopulated() {
        for category in CatalogCategory.allCases {
            #expect(!Catalog.entries(in: category).isEmpty, "\(category) is empty")
        }
        // entries(in:) preserves the flat shipped order within a category.
        let recombined = CatalogCategory.allCases.flatMap { Catalog.entries(in: $0) }
        #expect(recombined.map(\.id) == Catalog.entries.map(\.id))
    }

    @Test("the shaky Messenger and Signal schemes are dropped (verify-or-drop)")
    func droppedEntriesAreAbsent() {
        let names = Set(Catalog.entries.map(\.name))
        #expect(!names.contains("Messenger"))
        #expect(!names.contains("Signal"))
    }

    @Test("third-party app-scheme entries carry a Requires note; web and system-app schemes do not")
    func requiresNoteMatchesScheme() {
        // Schemes that reach the browser (http), a built-in handler (mailto/sms/tel),
        // or an always-present system app (itms-apps → App Store) never need a note —
        // only a third-party app scheme (things:, bear:, …) does.
        let noteless = ["http", "https", "mailto", "sms", "tel", "itms-apps"]
        for entry in Catalog.entries {
            let scheme = entry.definition.template.components(separatedBy: ":").first ?? ""
            if !noteless.contains(scheme) {
                #expect(entry.requiresApp != nil, "\(entry.name) needs a Requires note")
            }
        }
    }

    // MARK: - The default seeds

    @Test("the default seeds carry fixed seed.* ids in most-important-first order")
    func seedIDsAreFixedAndOrdered() {
        #expect(CatalogSeed.all.map(\.id) == [
            "seed.web-search", "seed.app-store-search", "seed.wikipedia", "seed.youtube", "seed.google-maps",
            "seed.link.youtube", "seed.link.gmail", "seed.link.github",
        ])
    }

    /// The static site seeds (ADR 0030) — slot-less links, so valid but *not*
    /// fallback-eligible, unlike the templated seeds.
    private static let staticSeedIDs: Set<String> = [
        "seed.link.youtube", "seed.link.gmail", "seed.link.github",
    ]

    @Test("every seed is saveable; templated seeds are fallback-eligible, static links are not")
    func seedsAreValidAndFallbackEligible() {
        for seed in CatalogSeed.all {
            #expect(seed.definition.isValidForSave, "\(seed.id) is not saveable")
            if Self.staticSeedIDs.contains(seed.id) {
                #expect(!seed.definition.isFallbackEligible, "\(seed.id) is a static link — not fallback-eligible")
                #expect(!seed.definition.hasSlot, "\(seed.id) is a static link — carries no slot")
            } else {
                #expect(seed.definition.isFallbackEligible, "\(seed.id) is not fallback-eligible")
            }
        }
    }

    @Test("the static site seeds appear in the Catalog's Sites section under their fixed ids")
    func staticSeedsAppearInSites() {
        let sites = Catalog.entries(in: .sites)
        for seed in [CatalogSeed.youTubeLink, CatalogSeed.gmail, CatalogSeed.gitHubLink] {
            let entry = sites.first { $0.id == seed.id }
            #expect(entry != nil, "\(seed.id) is missing from the Sites section")
            #expect(entry?.definition.template == seed.definition.template)
            #expect(entry?.definition.name == seed.definition.name)
            #expect(entry?.definition.glyph == seed.definition.glyph)
        }
    }

    @Test("the three non-web seeds appear in the catalog under their fixed ids, re-installing the seed verbatim")
    func seedsAppearInCatalog() {
        let byID = Dictionary(uniqueKeysWithValues: Catalog.entries.map { ($0.id, $0) })
        for seed in [CatalogSeed.wikipedia, CatalogSeed.youTube, CatalogSeed.googleMaps] {
            let entry = byID[seed.id]
            #expect(entry != nil, "\(seed.id) is missing from the catalog")
            // The re-install listing must not drift from the seed the pass plants.
            #expect(entry?.definition.template == seed.definition.template)
            #expect(entry?.definition.name == seed.definition.name)
            #expect(entry?.definition.aliases == seed.definition.aliases)
            #expect(entry?.definition.glyph == seed.definition.glyph)
        }
    }
}
