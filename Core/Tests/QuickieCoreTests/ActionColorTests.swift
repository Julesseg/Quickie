import Foundation
import Testing
@testable import QuickieCore

// An Action can wear a user-chosen **colour** from a curated token palette
// (CONTEXT.md → Action color; issue #243): the glyph's sibling customization. It is
// stored as a *token*, never a raw hex string, so light/dark legibility stays
// centrally tuned — and that tuning is what these tests pin, alongside the token's
// flow from definition → Action → widget snapshot and the Default (kind-derived)
// fallback that unset leaves untouched.
struct ActionColorTests {

    // MARK: - The palette itself

    @Test("the curated palette is a small, stable, deduped set")
    func paletteIsCurated() {
        let all = ActionColor.allCases
        // Ten tokens plus Default — which is the *absence* of a token, not a case.
        #expect(all.count == 10)
        #expect(Set(all.map(\.rawValue)).count == all.count)
        #expect(Set(all.map(\.label)).count == all.count)
        // Every token carries a non-empty human label for the picker.
        #expect(all.allSatisfy { !$0.label.isEmpty })
    }

    // The badge draws a **white** symbol on the token's fill, so every swatch must
    // clear WCAG's 3:1 non-text contrast floor against white — in *both* schemes.
    // This is the "tuned for legibility" acceptance criterion, enforced as arithmetic
    // rather than eyeballed: a future palette edit that dims a swatch fails here.
    @Test("every token keeps the white badge symbol legible in light and dark")
    func everyTokenIsLegibleAgainstWhite() {
        for color in ActionColor.allCases {
            let light = color.components(for: .light).contrastRatioAgainstWhite
            let dark = color.components(for: .dark).contrastRatioAgainstWhite
            #expect(light >= 3.0, "\(color.rawValue) light contrast \(light) < 3.0")
            #expect(dark >= 3.0, "\(color.rawValue) dark contrast \(dark) < 3.0")
        }
    }

    @Test("every token's channels are in range and its two schemes differ")
    func componentsAreWellFormed() {
        for color in ActionColor.allCases {
            for scheme in ActionColorScheme.allCases {
                let c = color.components(for: scheme)
                for channel in [c.red, c.green, c.blue] {
                    #expect(channel >= 0 && channel <= 1, "\(color.rawValue) channel out of range")
                }
            }
            // A palette entry that renders identically in both schemes would mean the
            // dark tuning was forgotten — the whole point of storing a token.
            #expect(color.components(for: .light) != color.components(for: .dark))
        }
    }

    @Test("the tokens are visually distinct — no two swatches share a fill")
    func tokensAreDistinct() {
        let lights = ActionColor.allCases.map { $0.components(for: .light) }
        #expect(Set(lights.map { "\($0.red)|\($0.green)|\($0.blue)" }).count == lights.count)
    }

    // MARK: - Token parsing: never a raw hex, unknown degrades to Default

    @Test("a known token round-trips through its raw value")
    func knownTokenRoundTrips() {
        for color in ActionColor.allCases {
            #expect(ActionColor(token: color.rawValue) == color)
        }
    }

    @Test("an unknown, blank, or hex-shaped token degrades to Default, never a colour")
    func unknownTokenDegradesToDefault() {
        #expect(ActionColor(token: nil) == nil)
        #expect(ActionColor(token: "") == nil)
        #expect(ActionColor(token: "   ") == nil)
        // A future build's token this one can't render: Default, never a crash.
        #expect(ActionColor(token: "chartreuse") == nil)
        // Raw hex is deliberately not a token — the palette is the only vocabulary.
        #expect(ActionColor(token: "#FF0000") == nil)
    }

    @Test("token parsing tolerates surrounding whitespace and case")
    func tokenParsingIsForgiving() {
        #expect(ActionColor(token: " green ") == .green)
        #expect(ActionColor(token: "GREEN") == .green)
    }

    // MARK: - The token flows onto the produced Action

    @Test("a chosen colour is stamped onto a slotted Custom Action")
    func slottedActionCarriesColor() {
        let def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}",
            color: .blue
        )
        #expect(def.makeAction(id: "things")?.color == .blue)
    }

    @Test("a chosen colour is stamped onto a static (slot-less) Custom Action")
    func staticActionCarriesColor() {
        let def = CustomActionDefinition(
            name: "GitHub",
            template: "https://github.com",
            color: .graphite
        )
        let action = def.makeAction(id: "gh")
        #expect(action?.kind == .quicklink)
        #expect(action?.color == .graphite)
    }

    @Test("no chosen colour leaves the Action's colour nil — the kind-derived tint applies")
    func unsetColorIsNil() {
        let slotted = CustomActionDefinition(name: "Search", template: "https://x.com/{q}")
        let staticLink = CustomActionDefinition(name: "Site", template: "https://x.com")
        #expect(slotted.makeAction(id: "a")?.color == nil)
        #expect(staticLink.makeAction(id: "b")?.color == nil)
    }

    @Test("colour and glyph are independent — either may be set alone")
    func colorAndGlyphAreIndependent() {
        let colorOnly = CustomActionDefinition(name: "A", template: "https://a.com", color: .pink)
        #expect(colorOnly.makeAction(id: "a")?.glyph == nil)
        #expect(colorOnly.makeAction(id: "a")?.color == .pink)

        let glyphOnly = CustomActionDefinition(name: "B", template: "https://b.com", glyph: "star")
        #expect(glyphOnly.makeAction(id: "b")?.glyph == "star")
        #expect(glyphOnly.makeAction(id: "b")?.color == nil)
    }

    // MARK: - Persistence bridge (the raw string the store holds)

    @Test("the definition exposes its colour as a storable token string")
    func definitionExposesToken() {
        #expect(CustomActionDefinition(name: "A", template: "https://a.com", color: .teal).colorToken == "teal")
        #expect(CustomActionDefinition(name: "A", template: "https://a.com").colorToken == nil)
    }

    @Test("a definition built from a stored token resolves it, and drops an unknown one")
    func definitionFromStoredToken() {
        #expect(CustomActionDefinition(name: "A", template: "https://a.com", colorToken: "orange").color == .orange)
        #expect(CustomActionDefinition(name: "A", template: "https://a.com", colorToken: "bogus").color == nil)
        #expect(CustomActionDefinition(name: "A", template: "https://a.com", colorToken: nil).color == nil)
    }

    // MARK: - The token rides the widget snapshot

    @Test("a widget projection carries the Action's colour token")
    func widgetActionCarriesColor() {
        let def = CustomActionDefinition(name: "Maps", template: "https://maps.example", color: .green)
        let action = def.makeAction(id: "maps")!
        let item = WidgetAction(action: action, glyph: "map")
        #expect(item.color == .green)
        #expect(item.colorToken == "green")
    }

    @Test("a snapshot round-trips the colour token")
    func snapshotRoundTripsColor() {
        let def = CustomActionDefinition(name: "Maps", template: "https://maps.example", color: .green)
        let item = WidgetAction(action: def.makeAction(id: "maps")!, glyph: "map")
        let decoded = FavoritesWidgetSnapshot.decode(FavoritesWidgetSnapshot.encode([item]))
        #expect(decoded.first?.color == .green)
    }

    // A widget running an older build must not fail the *whole* snapshot decode over
    // one token it doesn't know — it degrades that cell to the kind-derived tint.
    @Test("a snapshot carrying an unknown colour token still decodes, degrading to Default")
    func snapshotToleratesUnknownToken() {
        let json = """
        [{"id":"a","title":"A","glyph":"link","kind":"quicklink",\
        "colorToken":"chartreuse","execution":{"openApp":{}}}]
        """
        let decoded = FavoritesWidgetSnapshot.decode(Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded.first?.color == nil)
    }

    @Test("a legacy snapshot with no colour key decodes as Default")
    func snapshotWithoutColorKeyDecodes() {
        let json = """
        [{"id":"a","title":"A","glyph":"link","kind":"quicklink","execution":{"openApp":{}}}]
        """
        let decoded = FavoritesWidgetSnapshot.decode(Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded.first?.color == nil)
    }

    // MARK: - Seeds and Catalog ship sensible defaults

    @Test("every first-run seed ships a default colour token")
    func seedsShipColors() {
        for seed in CatalogSeed.all {
            #expect(seed.definition.color != nil, "seed \(seed.id) has no default colour")
        }
    }

    @Test("the named seeds wear their brand-appropriate colours")
    func seedColorsMatchBrands() {
        #expect(CatalogSeed.googleMaps.definition.color == .green)
        #expect(CatalogSeed.youTube.definition.color == .red)
        #expect(CatalogSeed.youTubeLink.definition.color == .red)
    }

    @Test("every Catalog entry ships a default colour token")
    func catalogEntriesShipColors() {
        for entry in Catalog.entries {
            #expect(entry.color != nil, "catalog entry \(entry.id) has no default colour")
        }
    }

    @Test("a Catalog entry's colour reaches the definition it installs")
    func catalogInstallCarriesColor() {
        for entry in Catalog.entries {
            #expect(entry.definition.color == entry.color, "catalog entry \(entry.id) drops its colour")
        }
    }

    // The Catalog's seed re-install rows are built from `CatalogSeed`, so their colour
    // must come from the seed too — otherwise re-installing a deleted seed would
    // silently produce a differently-coloured copy.
    @Test("a seed listed in the Catalog re-installs with the seed's own colour")
    func catalogSeedEntriesInheritSeedColor() {
        let maps = Catalog.entries.first { $0.id == CatalogSeed.googleMaps.id }
        #expect(maps?.color == CatalogSeed.googleMaps.definition.color)
    }
}
