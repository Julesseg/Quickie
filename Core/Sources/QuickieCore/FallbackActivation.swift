import Foundation

/// The pure rules that seed and migrate the single **enabled Fallback list**
/// (CONTEXT.md → Fallback list) — the only persisted fallback fact. Kept in Core,
/// EventKit- and UserDefaults-free, so the migration and first-run defaults are
/// exercised by `swift test` and the App's `FallbacksStore` is a thin edge wrapper
/// over them (the same pure-model / edge-store split as `ProviderEnablement`).
///
/// There is no stored fallback flag anymore: eligibility is `Action.isFallbackEligible`
/// (derived from shape) and *activation* is membership in the ordered enabled list.
/// The disabled pool is everything eligible but not enabled, so it is never stored.
///
/// The list-shaped rules below — reconcile, forgetting-prune, reorder — are the
/// **per-tier primitives**: `FallbackTiers` applies each of them to the Shelf as well,
/// because a Shelf member is reconciled and pruned by exactly the same rules as an
/// enabled one (ADR 0037), so each takes a neutral `list:` rather than naming a tier.
public enum FallbackActivation {
    /// The first-run enabled list, in most-important-first order: the **fallback-
    /// eligible** default seeds — web search, App Store search, Wikipedia, YouTube
    /// search, Google Maps — then the two permanent captures (CONTEXT.md → Fallback
    /// list, "ship pre-enabled"; issues #143, #144). The static site seeds (YouTube,
    /// Gmail, GitHub; ADR 0030) are **excluded** — they carry no free-text slot, so
    /// they are ineligible by shape and never enter the Fallback list. Newly eligible
    /// Actions are deliberately *not* auto-enabled — only these start active; everything
    /// else waits in the pool. The seed ids come from `CatalogSeed` (the same fixed ids
    /// the seed pass writes), the captures' from Core.
    public static func firstRunEnabledIDs() -> [String] {
        CatalogSeed.all.filter(\.definition.isFallbackEligible).map(\.id)
            + [Action.saveForLaterID, Action.newSnippetID]
    }

    /// One-time migration from the retired two-fact model (an ordered list plus a
    /// separate disabled set) to the single enabled list: **enabled = old order minus
    /// old disabled**, order preserved (CONTEXT.md → Fallback list; issue #114).
    /// Previously active fallbacks stay active in their old order; previously disabled
    /// ones fall out of the enabled list and so land in the derived pool.
    ///
    /// `firstRunDefaults` (the `firstRunEnabledIDs`) are appended before the disabled
    /// filter so a user whose legacy order predates a default — or who never opened
    /// the old page, leaving the order empty — still lands the pre-enabled trio, while
    /// one they had explicitly disabled is still removed.
    ///
    /// Deliberately does **not** filter against the live catalog: migration can run at
    /// launch before SwiftData's `@Query` has surfaced the just-seeded web-search row,
    /// so gating on "live" here would silently drop the pre-enabled default. Stale ids
    /// (a genuinely deleted Custom Action) are harmless — the engine gates every row on
    /// `Action.isFallbackEligible`, and `reconciled` hides them from the page
    /// — and real eligibility *loss* is forgotten by `prunedForgettingLost` instead.
    public static func migratedEnabledIDs(
        legacyOrder: [String],
        legacyDisabled: Set<String>,
        firstRunDefaults: [String]
    ) -> [String] {
        var base = legacyOrder
        for id in firstRunDefaults where !base.contains(id) { base.append(id) }
        var seen = Set<String>()
        return base.filter { !legacyDisabled.contains($0) && seen.insert($0).inserted }
    }

    /// One tier list **displayed** through the live fallback-eligible catalog: ids
    /// that don't currently resolve to an eligible Action are hidden (a deleted Custom
    /// Action, a Shortcut whose accepts-input is off), survivors keep their order. This
    /// is a non-destructive read for the engine's `enabledFallbacks` and the page's
    /// Shelf and Active sections — it hides without forgetting, so a value momentarily missing
    /// during load (before `@Query` populates) simply reappears once it resolves.
    /// Order-preserving and idempotent.
    public static func reconciled(
        list: [String],
        liveEligibleIDs: Set<String>
    ) -> [String] {
        var seen = Set<String>()
        return list.filter { liveEligibleIDs.contains($0) && seen.insert($0).inserted }
    }

    /// One tier list with **genuinely lost** eligibility forgotten (CONTEXT.md →
    /// Fallback list, "no memory of its rank"; issue #114): an id drops only if it was
    /// eligible earlier this session (`everEligible`) but no longer is (`liveEligible`)
    /// — a real loss (a Shortcut's accepts-input turned off, a Custom Action's first
    /// argument retyped, a delete/re-sync). An id that has **never yet** been seen
    /// eligible this session is kept, so a value not-yet-loaded at launch (the seeded
    /// web search before `@Query` surfaces it) is never mistaken for a loss and dropped.
    /// The App persists the result so regaining eligibility re-enters the action as a
    /// pool newcomer rather than at its old rank.
    ///
    /// **Known limit (narrow, accepted):** `everEligible` is session-scoped, so a loss
    /// that happens *while the app isn't running* — a CloudKit-synced edit that turns a
    /// Shortcut's accepts-input off — is indistinguishable at the next launch from a
    /// value not-yet-loaded, and is therefore *not* forgotten: the stale id stays in
    /// the list (hidden by `reconciled`), and a later re-gain would restore
    /// its old rank rather than land it in the pool. Forgetting only on *observed*
    /// losses is the deliberate trade for never false-dropping the launch-race seed;
    /// the alternative (forgetting any id absent at launch) would drop the pre-enabled
    /// web search before `@Query` surfaces it. The window is small — the id must lose
    /// eligibility out-of-session *and* later regain it — so it is left as-is.
    public static func prunedForgettingLost(
        list: [String],
        liveEligible: Set<String>,
        everEligible: Set<String>
    ) -> [String] {
        list.filter { id in
            !(everEligible.contains(id) && !liveEligible.contains(id))
        }
    }

    /// Applies a reorder of the **currently-visible** ids of one tier to its full list
    /// without dropping ids that aren't visible yet (issue #114). The Fallbacks
    /// page's sections show only ids that resolve against the loaded catalog, so
    /// a drag yields a permutation of that visible subset; an id still in the list but
    /// not yet loaded (the launch race) must keep its slot rather than be silently
    /// erased by a wholesale overwrite. Each visible slot in the list is filled from
    /// `visibleOrder` in sequence; non-visible ids stay exactly where they are. Any
    /// visible id short of `visibleOrder` keeps its own id (never fewer than present).
    public static func reordered(list: [String], visibleOrder: [String]) -> [String] {
        let visible = Set(visibleOrder)
        var next = visibleOrder.makeIterator()
        return list.map { visible.contains($0) ? (next.next() ?? $0) : $0 }
    }
}
