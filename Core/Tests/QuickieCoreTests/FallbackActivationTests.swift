import Foundation
import Testing
@testable import QuickieCore

// The pure seeding/migration rules behind the single enabled Fallback list
// (CONTEXT.md → Fallback list; issue #114). The App's FallbacksStore is a thin
// UserDefaults wrapper over these, so pinning them here is what "migration and
// first-run defaults covered by swift test" (the issue's acceptance criteria) means.
struct FallbackActivationTests {
    private let web = "seed.web-search"
    private var save: String { Action.saveForLaterID }
    private var new: String { Action.newSnippetID }

    @Test("fresh install pre-enables web search, Save for later, New Snippet — in that order")
    func firstRunDefaults() {
        #expect(FallbackActivation.firstRunEnabledIDs(webSearchID: web) == [web, save, new])
    }

    @Test("migration: enabled = old order minus old disabled, order preserved")
    func migrationDropsDisabledKeepsOrder() {
        let enabled = FallbackActivation.migratedEnabledIDs(
            legacyOrder: [web, "fb.gh", save, new],
            legacyDisabled: ["fb.gh"],
            firstRunDefaults: [web, save, new]
        )
        // fb.gh was disabled → falls to the pool; the rest stay active in old order.
        #expect(enabled == [web, save, new])
    }

    @Test("migration seeds the pre-enabled trio for a user whose legacy order was empty")
    func migrationSeedsDefaultsWhenLegacyEmpty() {
        // A user who never opened the old page has no persisted order — migration
        // still lands the pre-enabled trio.
        let enabled = FallbackActivation.migratedEnabledIDs(
            legacyOrder: [],
            legacyDisabled: [],
            firstRunDefaults: [web, save, new]
        )
        #expect(enabled == [web, save, new])
    }

    @Test("migration seeds defaults unconditionally — even before the catalog has loaded")
    func migrationSeedsDefaultsRegardlessOfCatalog() {
        // Migration runs at launch before @Query surfaces the just-seeded web-search
        // row, so it must not gate the pre-enabled default on a "live" set: the id is
        // seeded regardless and the engine gates rendering on eligibility.
        let enabled = FallbackActivation.migratedEnabledIDs(
            legacyOrder: [],
            legacyDisabled: [],
            firstRunDefaults: [web, save, new]
        )
        #expect(enabled.contains(web))
    }

    @Test("migration keeps a default the user had explicitly disabled out of the enabled list")
    func migrationRespectsDisabledDefault() {
        let enabled = FallbackActivation.migratedEnabledIDs(
            legacyOrder: [web, save, new],
            legacyDisabled: [save],           // user demoted Save for later
            firstRunDefaults: [web, save, new]
        )
        #expect(enabled == [web, new])        // save lands in the pool
    }

    @Test("reconcile hides ids absent from the live catalog, keeping survivors' order")
    func reconcileHidesAbsent() {
        let reconciled = FallbackActivation.reconciledEnabledIDs(
            enabled: [web, "fb.shortcut", save],
            liveEligibleIDs: [web, save]      // fb.shortcut turned accepts-input off
        )
        #expect(reconciled == [web, save])
    }

    @Test("reconcile is idempotent and order-preserving when nothing changed")
    func reconcileIdempotent() {
        let ids = [web, save, new]
        #expect(FallbackActivation.reconciledEnabledIDs(enabled: ids, liveEligibleIDs: Set(ids)) == ids)
    }

    @Test("forgetting-prune drops an id only after it was seen eligible then lost")
    func pruneForgetsGenuineLoss() {
        // fb.shortcut was eligible earlier this session, now isn't → a real loss, drop
        // it with no rank memory.
        let pruned = FallbackActivation.prunedForgettingLost(
            enabled: [web, "fb.shortcut", save],
            liveEligible: [web, save],
            everEligible: [web, "fb.shortcut", save]
        )
        #expect(pruned == [web, save])
    }

    @Test("forgetting-prune keeps a not-yet-loaded id (never seen eligible this session)")
    func pruneKeepsNotYetLoaded() {
        // web was seeded into the enabled list but @Query hasn't surfaced it yet, so it
        // isn't live *and* was never seen eligible — it must be kept, not mistaken for a
        // loss (the launch race the pre-enable depends on).
        let pruned = FallbackActivation.prunedForgettingLost(
            enabled: [web, save, new],
            liveEligible: [save, new],
            everEligible: [save, new]
        )
        #expect(pruned == [web, save, new])
    }
}
