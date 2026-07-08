import Foundation
import Observation
import QuickieCore

/// Owns the single **enabled Fallback list** (CONTEXT.md → Fallback list; issue
/// #114): the user's explicit, most-important-first order over the Fallback Actions
/// they've *activated* — the only persisted fallback fact. The disabled pool is
/// derived (everything eligible but not enabled), so it is never stored, and there
/// is no separate disabled set anymore.
///
/// Persisted in the shared App Group's `UserDefaults` so it survives launches and
/// the Share Extension reads the same source of truth (ADR 0006), mirroring
/// `SignalsStore`. The list spans stored Custom Actions, accepts-input Shortcuts,
/// *and* the two permanent built-in captures — none of which share a single SwiftData
/// column — so it lives here as an id list. Eligibility itself is derived live from
/// `Action.isFallbackEligible`; this store only records which eligible ids are active
/// and in what order, reconciling against the live eligible set on read.
@MainActor
@Observable
final class FallbacksStore {
    /// The two permanent, demote-but-never-delete built-in captures. Their ids match
    /// the Core factories so the persisted list lines up with the Actions.
    static let saveForLaterID = Action.saveForLaterID
    static let newSnippetID = Action.newSnippetID
    static let permanentIDs = [saveForLaterID, newSnippetID]

    /// The pre-Pile id of the "New Note" capture (ADR 0018): mapped to Save for later
    /// on read so a user's old position carries over.
    private static let legacyNewNoteID = "builtin.new-note"

    /// The persisted enabled list, most-important-first. May contain an id that has
    /// since lost eligibility until `pruneToEligible` runs; `resolvedEnabled(for:)`
    /// filters it for reads.
    private(set) var enabled: [String]

    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "fallbacks.enabled"
    /// Set once the one-time migration from the retired two-fact model has run.
    private static let migratedKey = "fallbacks.didMigrateToEnabledList"
    /// The retired persistence: an ordered list plus a separate disabled set. Read
    /// only by the migration, then never again.
    private static let legacyOrderKey = "fallbacks.order"
    private static let legacyDisabledKey = "fallbacks.disabled"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        self.enabled = (defaults.stringArray(forKey: Self.enabledKey) ?? [])
            .map(Self.remapLegacyID)
    }

    static func launch() -> FallbacksStore {
        // Honors the same UI-test reset flag as SignalsStore (shared constant), so a
        // test asking for a clean launcher also gets a clean, unmigrated Fallback
        // list — the enabled list and the migration flag reset alongside Favorites.
        if ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
            let defaults = SignalsStore.sharedDefaults
            for key in [enabledKey, migratedKey, legacyOrderKey, legacyDisabledKey] {
                defaults.removeObject(forKey: key)
            }
        }
        return FallbacksStore()
    }

    private static func remapLegacyID(_ id: String) -> String {
        id == legacyNewNoteID ? saveForLaterID : id
    }

    /// One-time migration/seed to the single enabled list (issue #114). Idempotent —
    /// guarded by `migratedKey` — and safe to call every launch. Deliberately does not
    /// consult the live catalog: it can run before SwiftData's `@Query` surfaces the
    /// just-seeded web-search row, so gating the pre-enabled default on "live" would
    /// drop it. Stale ids are hidden by `resolvedEnabled` and forgotten by
    /// `pruneToEligible` once genuinely lost.
    func migrateIfNeeded(firstRunDefaults: [String]) {
        guard !defaults.bool(forKey: Self.migratedKey) else { return }
        let legacyOrder = (defaults.stringArray(forKey: Self.legacyOrderKey) ?? [])
            .map(Self.remapLegacyID)
        let legacyDisabled = Set((defaults.stringArray(forKey: Self.legacyDisabledKey) ?? [])
            .map(Self.remapLegacyID))
        enabled = FallbackActivation.migratedEnabledIDs(
            legacyOrder: legacyOrder,
            legacyDisabled: legacyDisabled,
            firstRunDefaults: firstRunDefaults
        )
        persist()
        defaults.set(true, forKey: Self.migratedKey)
    }

    /// Whether an id is currently in the enabled list.
    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    /// The enabled list resolved to the live eligible ids, most-important-first — the
    /// engine's `enabledFallbacks` and the page's enabled section. Ids that no longer
    /// resolve to an eligible Action drop out (no rank memory), survivors keep order.
    func resolvedEnabled(for liveEligibleIDs: [String]) -> [String] {
        FallbackActivation.reconciledEnabledIDs(enabled: enabled, liveEligibleIDs: Set(liveEligibleIDs))
    }

    /// The derived **disabled pool**: the eligible ids not in the enabled list. The
    /// page sorts these alphabetically by title (titles live App-side); the store only
    /// knows ids, so it returns membership.
    func pool(from liveEligibleIDs: [String]) -> [String] {
        liveEligibleIDs.filter { !enabled.contains($0) }
    }

    /// **Promotes** a pooled fallback to the **bottom** of the enabled section
    /// (CONTEXT.md → Fallback list): promotion says "available", not "most important".
    func promote(_ id: String) {
        guard !enabled.contains(id) else { return }
        enabled.append(id)
        persist()
    }

    /// **Demotes** an enabled fallback back to the derived pool — the red minus. The
    /// built-in captures are demotable but never leave the page (they stay eligible,
    /// so they reappear in the pool). Nothing here deletes anything.
    func demote(_ id: String) {
        guard enabled.contains(id) else { return }
        enabled.removeAll { $0 == id }
        persist()
    }

    /// Replaces the enabled list wholesale — the internal write behind migration and
    /// the forgetting-prune, which have already computed the exact list to persist.
    /// The Fallbacks page's reorder does **not** use this (it would drop not-yet-loaded
    /// ids); it routes through `reorderEnabled` instead.
    func setEnabled(_ ids: [String]) {
        enabled = ids
        persist()
    }

    /// Applies a drag-reorder of the **visible** Active rows without dropping an enabled
    /// id that hasn't resolved yet (issue #114). The page shows only ids that resolve
    /// against the loaded catalog, so `visibleOrder` is a permutation of that subset; an
    /// id still in `enabled` but not yet loaded (the launch race) keeps its slot rather
    /// than being erased by a wholesale overwrite — the same not-yet-loaded-vs-lost care
    /// `pruneToEligible` takes. Persists only when the order actually changed.
    func reorderEnabled(visibleOrder: [String]) {
        let reordered = FallbackActivation.reorderedEnabled(enabled: enabled, visibleOrder: visibleOrder)
        if reordered != enabled {
            enabled = reordered
            persist()
        }
    }

    /// Forgets an id's rank once its eligibility is **genuinely lost** (issue #114) —
    /// called when the eligible catalog changes. An id drops only if it was seen
    /// eligible earlier this session (`everEligible`) but no longer is (`liveEligible`):
    /// a real loss (a Shortcut's accepts-input turned off, a Custom Action retyped or
    /// deleted), regaining eligibility re-enters it as a pool newcomer. An id never yet
    /// seen eligible — the seeded web search before `@Query` surfaces it — is kept, so
    /// the launch-race pre-enable survives. A no-op before migration and when unchanged.
    func pruneToEligible(liveEligible: [String], everEligible: Set<String>) {
        guard defaults.bool(forKey: Self.migratedKey) else { return }
        let pruned = FallbackActivation.prunedForgettingLost(
            enabled: enabled, liveEligible: Set(liveEligible), everEligible: everEligible
        )
        if pruned != enabled { setEnabled(pruned) }
    }

    private func persist() {
        defaults.set(enabled, forKey: Self.enabledKey)
    }
}
