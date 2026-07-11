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

    @Test("every catalog entry's template parses, carries ≥ 1 slot, and is schemed")
    func everyEntryIsValid() {
        for entry in Catalog.entries {
            let def = entry.definition
            #expect(def.hasSlot, "\(entry.name) has no {slot}")
            #expect(def.urlIsSchemedAfterProbe, "\(entry.name) is not schemed")
            #expect(def.isValidForSave, "\(entry.name) fails the Save gates")
            #expect(def.makeAction(id: entry.id) != nil, "\(entry.name) factories no Action")
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

    // MARK: - The four default seeds

    @Test("the default seeds carry fixed seed.* ids in most-important-first order")
    func seedIDsAreFixedAndOrdered() {
        #expect(CatalogSeed.all.map(\.id) == [
            "seed.web-search", "seed.app-store-search", "seed.wikipedia", "seed.youtube", "seed.google-maps",
        ])
    }

    @Test("every seed definition is a valid, fallback-eligible Custom Action")
    func seedsAreValidAndFallbackEligible() {
        for seed in CatalogSeed.all {
            #expect(seed.definition.isValidForSave, "\(seed.id) is not saveable")
            #expect(seed.definition.isFallbackEligible, "\(seed.id) is not fallback-eligible")
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
        }
    }
}
