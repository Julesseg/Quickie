import Foundation
import Observation
import QuickieCore

/// Owns the user's **fallback tiers** (CONTEXT.md → Fallback list, Shelf; issues
/// #114, #241): the ordered **Shelf** and the ordered **enabled** (Active) list — the
/// only persisted fallback facts. The disabled pool is derived (everything eligible
/// that neither list claims), so it is never stored, and there is no separate disabled
/// set anymore.
///
/// Persisted in the shared App Group's `UserDefaults` so it survives launches and
/// the Share Extension reads the same source of truth (ADR 0006), mirroring
/// `SignalsStore`. The lists span stored Custom Actions, accepts-input Shortcuts,
/// *and* the built-in captures — none of which share a single SwiftData column — so
/// they live here as id lists. Eligibility itself is derived live from
/// `Action.isFallbackEligible`; this store only records which eligible ids sit on which
/// rung and in what order, reconciling against the live eligible set on read.
///
/// Every placement rule — promotion to the Shelf removing an id from Active, demotion
/// from the Shelf landing at the *top* of Active, the two lists staying disjoint —
/// lives in Core's `FallbackTiers`, so this is a thin persistence wrapper over it (the
/// same pure-model / edge-store split as `ProviderEnablement`).
@MainActor
@Observable
final class FallbacksStore {
    /// The two permanent, demote-but-never-delete built-in captures. Their ids match
    /// the Core factories so the persisted lists line up with the Actions.
    static let saveForLaterID = Action.saveForLaterID
    static let newSnippetID = Action.newSnippetID
    static let permanentIDs = [saveForLaterID, newSnippetID]

    /// The pre-Pile id of the "New Note" capture (ADR 0018): mapped to Save for later
    /// on read so a user's old position carries over.
    private static let legacyNewNoteID = "builtin.new-note"

    /// The persisted ladder: the Shelf and the enabled list, each most-important-first.
    /// Either may hold an id that has since lost eligibility until `pruneToEligible`
    /// runs; the `resolved…` reads filter them for display.
    private(set) var tiers: FallbackTiers

    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "fallbacks.enabled"
    private static let shelfKey = "fallbacks.shelf"
    /// Set once the one-time migration from the retired two-fact model has run.
    private static let migratedKey = "fallbacks.didMigrateToEnabledList"
    /// Set once the Shelf tier has been seeded with its four defaults (issue #241).
    /// Kept separate from `migratedKey` so an existing user — already migrated to the
    /// single enabled list — still gets the Shelf on this build's first launch, and so
    /// a user who empties the Shelf never has it seeded back under them.
    private static let seededShelfKey = "fallbacks.didSeedShelf"
    /// The retired persistence: an ordered list plus a separate disabled set. Read
    /// only by the migration, then never again.
    private static let legacyOrderKey = "fallbacks.order"
    private static let legacyDisabledKey = "fallbacks.disabled"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        self.tiers = FallbackTiers(
            shelf: (defaults.stringArray(forKey: Self.shelfKey) ?? []).map(Self.remapLegacyID),
            enabled: (defaults.stringArray(forKey: Self.enabledKey) ?? []).map(Self.remapLegacyID)
        )
    }

    static func launch() -> FallbacksStore {
        // Cleared under UI testing so a test asking for a clean launcher gets a
        // clean, unmigrated Fallback list — both tiers and the migration/seed flags
        // reset alongside Favorites. Keyed on `--uitesting` as well as the explicit
        // reset flag, for the same reason as `ProviderEnablementStore.launch()`:
        // the lists live in the *persistent* App Group defaults, which
        // outlive the ephemeral store, so a suite launching with plain `--uitesting`
        // (PileUITests does) would inherit whatever an earlier suite on the same
        // simulator left active — and a list missing "Save for later" makes the
        // always-present capture vanish. That is exactly how PileUITests failed once
        // a shard reshuffle put a fallback-mutating suite ahead of it, and why
        // SecondaryActionUITests had to reach for the reset flag by hand. Safe to
        // widen: no test drives fallback state across two launches.
        if ProcessInfo.processInfo.arguments.contains("--uitesting")
            || ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
            let defaults = SignalsStore.sharedDefaults
            for key in [enabledKey, shelfKey, migratedKey, seededShelfKey, legacyOrderKey, legacyDisabledKey] {
                defaults.removeObject(forKey: key)
            }
            // …but a UI-test launch starts with an **empty Shelf**: stamping the seed
            // flag makes `migrateIfNeeded` skip it (issue #241). The default Shelf
            // claims Save for later and New Snippet off the Active list, and a suite
            // that taps a capture in the bottom fallback region — PileUITests,
            // SecondaryActionUITests — would then be asserting against a row the
            // *shelf* now owns, testing the seed rather than its own subject. So the
            // seeded membership is pinned where it belongs (Core's FallbackTiers
            // tests) and every UI test that cares about the Shelf promotes its own
            // members explicitly, exactly as it already does for Active. Same
            // determinism argument as the reset above: a suite should never inherit
            // fallback state it didn't set.
            defaults.set(true, forKey: seededShelfKey)
        }
        return FallbacksStore()
    }

    private static func remapLegacyID(_ id: String) -> String {
        id == legacyNewNoteID ? saveForLaterID : id
    }

    /// One-time migration/seed of both tiers (issues #114, #241). Idempotent — each
    /// half guarded by its own flag — and safe to call every launch. Deliberately does
    /// not consult the live catalog: it can run before SwiftData's `@Query` surfaces
    /// the just-seeded web-search row, so gating the pre-enabled default on "live"
    /// would drop it. Stale ids are hidden by the `resolved…` reads and forgotten by
    /// `pruneToEligible` once genuinely lost.
    ///
    /// The enabled half runs first, then the Shelf seed: `FallbackTiers`' shelf-wins
    /// rule is what settles the overlap, so a fresh install and an existing user's
    /// carried-over list both end up with Save for later and New Snippet on the Shelf
    /// and everything else untouched in Active.
    func migrateIfNeeded(firstRunDefaults: [String]) {
        if !defaults.bool(forKey: Self.migratedKey) {
            let legacyOrder = (defaults.stringArray(forKey: Self.legacyOrderKey) ?? [])
                .map(Self.remapLegacyID)
            let legacyDisabled = Set((defaults.stringArray(forKey: Self.legacyDisabledKey) ?? [])
                .map(Self.remapLegacyID))
            tiers = FallbackTiers(
                shelf: tiers.shelf,
                enabled: FallbackActivation.migratedEnabledIDs(
                    legacyOrder: legacyOrder,
                    legacyDisabled: legacyDisabled,
                    firstRunDefaults: firstRunDefaults
                )
            )
            // Persisted unconditionally, unlike the change-guarded edits below: the
            // flag is about to say "already migrated", so the computed lists must be
            // on disk even in the degenerate case where they match what was read.
            persist()
            defaults.set(true, forKey: Self.migratedKey)
        }
        if !defaults.bool(forKey: Self.seededShelfKey) {
            tiers = FallbackTiers(shelf: FallbackTiers.firstRunShelfIDs, enabled: tiers.enabled)
            persist()
            defaults.set(true, forKey: Self.seededShelfKey)
        }
    }

    /// The enabled list resolved to the live eligible ids, most-important-first — the
    /// engine's `enabledFallbacks` and the page's Active section. Ids that no longer
    /// resolve to an eligible Action drop out (no rank memory), survivors keep order.
    /// A **shelved** action is deliberately absent: it has vacated the bottom region.
    func resolvedEnabled(for liveEligibleIDs: [String]) -> [String] {
        tiers.resolvedEnabled(for: liveEligibleIDs)
    }

    /// The Shelf resolved to the live eligible ids, most-important-first — the page's
    /// Shelf section and (issue #242) the glass button row above the input.
    func resolvedShelf(for liveEligibleIDs: [String]) -> [String] {
        tiers.resolvedShelf(for: liveEligibleIDs)
    }

    /// The derived **disabled pool**: the eligible ids neither tier claims. The page
    /// sorts these alphabetically by title (titles live App-side); the store only knows
    /// ids, so it returns membership.
    func pool(from liveEligibleIDs: [String]) -> [String] {
        tiers.pool(from: liveEligibleIDs)
    }

    /// Moves a fallback between the ladder's rungs — the page's plus/minus/shelf
    /// affordances. Placement is Core's (`FallbackTiers.move`): promotion appends
    /// ("available", not "most important"), a demotion off the Shelf lands at the
    /// **top** of Active, and the tiers stay disjoint. Persists only on a real change,
    /// so re-tapping a row can never quietly re-sort a list.
    func move(_ id: String, to tier: FallbackTier) {
        edit { $0.move(id, to: tier) }
    }

    /// Applies a drag-reorder of the **visible** Shelf rows without dropping a member
    /// that hasn't resolved yet (issue #114). The page shows only ids that resolve
    /// against the loaded catalog, so `visibleOrder` is a permutation of that subset; an
    /// id still stored but not yet loaded (the launch race) keeps its slot rather
    /// than being erased by a wholesale overwrite — the same not-yet-loaded-vs-lost care
    /// `pruneToEligible` takes. Persists only when the order actually changed.
    func reorderShelf(visibleOrder: [String]) {
        edit { $0.reorderShelf(visibleOrder: visibleOrder) }
    }

    /// Applies a drag-reorder of the **visible** Active rows, with the same
    /// not-yet-loaded care as `reorderShelf`.
    func reorderEnabled(visibleOrder: [String]) {
        edit { $0.reorderEnabled(visibleOrder: visibleOrder) }
    }

    /// Demotes any id that is currently **instance-disabled** off *both* tiers,
    /// coupling the per-action Disabled switch with the fallback ladder: a disabled
    /// action leaves the Shelf or the Active section for the Available pool, and —
    /// removed from both lists — a later re-enable leaves it in Available rather than
    /// restoring its old rank. Called whenever the disabled set changes, from any
    /// surface, so the coupling is uniform. Persists only on a change.
    func demoteDisabled(_ disabledIDs: Set<String>) {
        edit { $0.demoteToPool(disabledIDs) }
    }

    /// Forgets an id's rank on **either** tier once its eligibility is *genuinely* lost
    /// (issue #114) — called when the eligible catalog changes. An id drops only if it
    /// was seen eligible earlier this session (`everEligible`) but no longer is:
    /// a real loss (a Shortcut's accepts-input turned off, a Custom Action retyped or
    /// deleted), regaining eligibility re-enters it as a pool newcomer. An id never yet
    /// seen eligible — the seeded web search before `@Query` surfaces it — is kept, so
    /// the launch-race pre-enable survives. A no-op before migration and when unchanged.
    func pruneToEligible(liveEligible: [String], everEligible: Set<String>) {
        guard defaults.bool(forKey: Self.migratedKey) else { return }
        edit { $0.pruneForgettingLost(liveEligible: Set(liveEligible), everEligible: everEligible) }
    }

    /// The single edit path: applies a Core mutation to a copy of the ladder and swaps
    /// it in, but only when something actually moved — so the observable value never
    /// churns and the defaults are not rewritten on a no-op tap.
    private func edit(_ mutate: (inout FallbackTiers) -> Void) {
        var next = tiers
        mutate(&next)
        guard next != tiers else { return }
        tiers = next
        persist()
    }

    private func persist() {
        defaults.set(tiers.enabled, forKey: Self.enabledKey)
        defaults.set(tiers.shelf, forKey: Self.shelfKey)
    }
}
