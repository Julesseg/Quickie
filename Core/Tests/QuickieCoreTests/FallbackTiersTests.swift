import Foundation
import Testing
@testable import QuickieCore

// The three-tier promotion ladder behind the Fallbacks page — pool → enabled →
// Shelf (CONTEXT.md → Fallback list, Shelf; ADR 0037; issue #241). The App's
// `FallbacksStore` is a thin UserDefaults wrapper over this value, so the placement
// rules ("promoting to the Shelf removes it from Active", "demoting from the Shelf
// lands at the *top* of Active"), the disjointness invariant, and the eligibility
// pruning are all pinned here — that is what the issue's "pure rules covered by Core
// behavior tests" means.
struct FallbackTiersTests {
    private let web = "seed.web-search"
    private let maps = "seed.google-maps"
    private var save: String { Action.saveForLaterID }
    private var snippet: String { Action.newSnippetID }
    private var reminder: String { Action.newReminderID }
    private var event: String { Action.newEventID }

    // MARK: - Membership

    @Test("the two lists are disjoint by construction — a shelved id never stays enabled")
    func constructionSubtractsShelfFromEnabled() {
        // The migration hands over an existing enabled list *and* the seeded shelf;
        // the ids the shelf claims must leave the enabled list rather than ride both.
        let tiers = FallbackTiers(shelf: [save, snippet], enabled: [web, save, maps, snippet])
        #expect(tiers.shelf == [save, snippet])
        #expect(tiers.enabled == [web, maps])
    }

    @Test("construction drops duplicates within each list, keeping first position")
    func constructionDedupes() {
        let tiers = FallbackTiers(shelf: [save, save], enabled: [web, maps, web])
        #expect(tiers.shelf == [save])
        #expect(tiers.enabled == [web, maps])
    }

    @Test("tier(of:) reports the ladder rung an id sits on; anything else is the pool")
    func tierReportsMembership() {
        let tiers = FallbackTiers(shelf: [save], enabled: [web])
        #expect(tiers.tier(of: save) == .shelf)
        #expect(tiers.tier(of: web) == .enabled)
        #expect(tiers.tier(of: maps) == .pool)
    }

    // MARK: - Moving between tiers

    @Test("promoting an active fallback to the Shelf removes it from Active")
    func promoteEnabledToShelf() {
        var tiers = FallbackTiers(shelf: [], enabled: [web, maps, save])
        tiers.move(maps, to: .shelf)
        #expect(tiers.shelf == [maps])
        #expect(tiers.enabled == [web, save])
    }

    @Test("promoting to the Shelf appends at the trailing end of the shelf order")
    func promoteToShelfAppends() {
        var tiers = FallbackTiers(shelf: [reminder, event], enabled: [maps])
        tiers.move(maps, to: .shelf)
        #expect(tiers.shelf == [reminder, event, maps])
    }

    @Test("a pool row can be promoted straight to the Shelf — no forced two-step climb")
    func promotePoolDirectlyToShelf() {
        var tiers = FallbackTiers(shelf: [], enabled: [web])
        tiers.move(maps, to: .shelf)          // maps was in the pool
        #expect(tiers.shelf == [maps])
        #expect(tiers.enabled == [web])
    }

    @Test("a pool row promoted to Active lands at the bottom — promotion says available, not important")
    func promotePoolToEnabledAppends() {
        var tiers = FallbackTiers(shelf: [], enabled: [web, save])
        tiers.move(maps, to: .enabled)
        #expect(tiers.enabled == [web, save, maps])
    }

    @Test("demoting from the Shelf inserts at the *top* of Active, not the bottom")
    func demoteShelfToTopOfEnabled() {
        // It was important enough to shelve, so it does not fall to the bottom
        // (CONTEXT.md → Fallback list).
        var tiers = FallbackTiers(shelf: [reminder, save], enabled: [web, maps])
        tiers.move(save, to: .enabled)
        #expect(tiers.shelf == [reminder])
        #expect(tiers.enabled == [save, web, maps])
    }

    @Test("demoting to the pool removes an id from whichever tier held it")
    func demoteToPool() {
        var tiers = FallbackTiers(shelf: [save], enabled: [web, maps])
        tiers.move(maps, to: .pool)
        tiers.move(save, to: .pool)
        #expect(tiers.shelf == [])
        #expect(tiers.enabled == [web])
    }

    @Test("moving an id to the tier it already occupies keeps its rank")
    func moveToOwnTierIsANoOp() {
        var tiers = FallbackTiers(shelf: [reminder, event], enabled: [web, maps])
        tiers.move(reminder, to: .shelf)
        tiers.move(web, to: .enabled)
        #expect(tiers.shelf == [reminder, event])
        #expect(tiers.enabled == [web, maps])
    }

    @Test("a pooled id demoted to the pool changes nothing")
    func poolToPoolIsANoOp() {
        var tiers = FallbackTiers(shelf: [save], enabled: [web])
        tiers.move(maps, to: .pool)
        #expect(tiers == FallbackTiers(shelf: [save], enabled: [web]))
    }

    // MARK: - Derived reads

    @Test("the pool is everything eligible that neither tier claims")
    func poolIsDerived() {
        let tiers = FallbackTiers(shelf: [save], enabled: [web])
        #expect(tiers.pool(from: [web, maps, save, snippet]) == [maps, snippet])
    }

    @Test("both tiers resolve through the live eligible catalog, hiding what doesn't load")
    func resolvedHidesAbsentIDs() {
        let tiers = FallbackTiers(shelf: [save, "fb.shortcut"], enabled: [web, "fb.gone", maps])
        #expect(tiers.resolvedShelf(for: [save, web, maps]) == [save])
        #expect(tiers.resolvedEnabled(for: [save, web, maps]) == [web, maps])
    }

    // MARK: - Reorder

    @Test("the Shelf drag-reorders its own list without touching Active")
    func reorderShelf() {
        var tiers = FallbackTiers(shelf: [reminder, event, save], enabled: [web, maps])
        tiers.reorderShelf(visibleOrder: [save, reminder, event])
        #expect(tiers.shelf == [save, reminder, event])
        #expect(tiers.enabled == [web, maps])
    }

    @Test("a Shelf reorder keeps a not-yet-loaded member in its slot")
    func reorderShelfKeepsUnresolved() {
        // The page only shows ids that resolve against the loaded catalog, so a drag
        // is a permutation of the *visible* subset — the launch-race id must not be
        // erased by a wholesale overwrite (the same care `reorderEnabled` takes).
        var tiers = FallbackTiers(shelf: [reminder, "fb.pending", event], enabled: [])
        tiers.reorderShelf(visibleOrder: [event, reminder])
        #expect(tiers.shelf == [event, "fb.pending", reminder])
    }

    @Test("Active drag-reorders its own list without touching the Shelf")
    func reorderEnabled() {
        var tiers = FallbackTiers(shelf: [reminder, event], enabled: [web, maps, save])
        tiers.reorderEnabled(visibleOrder: [save, web, maps])
        #expect(tiers.enabled == [save, web, maps])
        #expect(tiers.shelf == [reminder, event])
    }

    // MARK: - Pruning

    @Test("eligibility loss prunes a Shelf member exactly like an enabled one")
    func pruneForgetsLostFromBothTiers() {
        // Both ids were seen eligible earlier this session and no longer are — a real
        // loss, so both forget their rank and re-enter as pool newcomers on re-gain.
        var tiers = FallbackTiers(shelf: [save, "fb.shortcut"], enabled: [web, "fb.custom"])
        tiers.pruneForgettingLost(
            liveEligible: [save, web],
            everEligible: [save, web, "fb.shortcut", "fb.custom"]
        )
        #expect(tiers.shelf == [save])
        #expect(tiers.enabled == [web])
    }

    @Test("pruning keeps a not-yet-loaded member of either tier")
    func pruneKeepsNotYetLoaded() {
        // Nothing here was ever seen eligible this session — the launch race, not a
        // loss — so both tiers survive intact.
        var tiers = FallbackTiers(shelf: [save], enabled: [web])
        tiers.pruneForgettingLost(liveEligible: [], everEligible: [])
        #expect(tiers.shelf == [save])
        #expect(tiers.enabled == [web])
    }

    @Test("instance-disabling a shelved action demotes it to the pool, like an enabled one")
    func disablingDemotesFromBothTiers() {
        var tiers = FallbackTiers(shelf: [reminder, save], enabled: [web, maps])
        tiers.demoteToPool(Set([reminder, maps]))
        #expect(tiers.shelf == [save])
        #expect(tiers.enabled == [web])
    }

    // MARK: - First run and migration

    @Test("first run ships the Shelf as New Reminder, New Event, Save for later, New Snippet")
    func firstRunShelf() {
        #expect(FallbackTiers.firstRunShelfIDs == [reminder, event, save, snippet])
    }

    @Test("first run seeds both tiers, the shelf claiming the two captures off the enabled list")
    func firstRunTiers() {
        // The enabled defaults still name Save for later and New Snippet; the seeded
        // Shelf takes them, leaving Active as the five search seeds.
        let tiers = FallbackTiers(
            shelf: FallbackTiers.firstRunShelfIDs,
            enabled: FallbackActivation.firstRunEnabledIDs()
        )
        #expect(tiers.shelf == [reminder, event, save, snippet])
        #expect(tiers.enabled == [
            web, "seed.app-store-search", "seed.wikipedia", "seed.youtube", maps,
        ])
    }

    @Test("migration seeds the Shelf and carries an existing enabled list over otherwise untouched")
    func migrationCarriesEnabledOver() {
        let tiers = FallbackTiers(
            shelf: FallbackTiers.firstRunShelfIDs,
            enabled: [maps, web, save, "fb.custom", snippet]
        )
        #expect(tiers.shelf == [reminder, event, save, snippet])
        // Only the two ids the Shelf claimed left; the user's order is otherwise intact.
        #expect(tiers.enabled == [maps, web, "fb.custom"])
    }

    @Test("the seeded Shelf claims all four ids even when the user's enabled list lacks them")
    func migrationSeedsShelfIDsAbsentFromEnabled() {
        // The deliberate reading of "the Shelf ships as New Reminder, New Event, Save
        // for later, New Snippet" (issue #241): the seed is the *whole* list, not the
        // subset that happens to be active. New Reminder and New Event were never in
        // `firstRunEnabledIDs`, so for **every** existing user they are absent from
        // `enabled` — gating the seed on presence there would mean they never reach the
        // Shelf at all. The cost is the mirror case, pinned here too: a user who had
        // demoted Save for later to the pool pre-#241 gets it back, on the Shelf.
        let tiers = FallbackTiers(
            shelf: FallbackTiers.firstRunShelfIDs,
            enabled: [web, maps, snippet]          // no save (demoted), no reminder/event
        )
        #expect(tiers.shelf == [reminder, event, save, snippet])
        #expect(tiers.enabled == [web, maps])
    }
}
