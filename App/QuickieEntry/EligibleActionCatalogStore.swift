import Foundation
import QuickieCore
import QuickieStoreKit
import WidgetKit

/// The App Group edge of the **eligible-action catalog** (ADR 0027) — the second
/// published snapshot beside the Favorites one, shared by the processes that touch
/// it (which is why it lives in the folder synced into both the app and widget
/// targets, like `FavoritesWidgetStore`):
///
/// - The app is the **single writer** (`publish`, rewritten publish-only-on-change
///   whenever the eligible set moves — any create, edit, delete, enable, or disable
///   touching an eligible Action).
/// - The [[Actions widget]]'s picker + timeline and the [[Action control]]'s picker
///   + value provider only ever `load` it — the picker enumerates it and the render
///   surfaces `EligibleActionCatalog.resolve` their configured ids against it. The
///   widget process never opens SwiftData (ADR 0027).
///
/// The configuration (which ids a placed instance chose) lives in each instance's
/// `AppIntentConfiguration`, not here — this store holds only the *catalog*, the
/// data those ids join against. The codec is Core (`EligibleActionCatalog`) so the
/// write, read, and id-join are `swift test`-covered; this is only the thin keyed
/// edge. Frecency for a widget/control run rides the **shared outbox**
/// (`FavoritesWidgetStore.recordRun`), so there is no second outbox here.
enum EligibleActionCatalogStore {
    /// The Actions widget's WidgetKit kind — held beside the catalog its timeline
    /// joins against, so the app's `reloadTimelines(ofKind:)` and the widget's
    /// configuration can never drift onto different identities.
    static let widgetKind = "QuickieActionsWidget"

    /// The Action control's kind — the identity Control Center addresses it by, and
    /// the app reloads when the catalog changes so a renamed or deleted configured
    /// action re-renders (or falls back) without the user re-opening its config.
    static let controlKind = "QuickieActionControl"

    private static let catalogKey = "widget.catalog"

    /// The shared App Group defaults — the same instance every launcher store uses,
    /// so the app's writes and the widget process's reads meet on one suite.
    private static var defaults: UserDefaults { AppGroup.defaults }

    /// Writes the denormalized catalog, but **only when it actually changed** — the
    /// caller recomputes it per engine rebuild, and an unconditional write would be
    /// churn plus a pointless reload. Returns whether anything was written, so the
    /// caller pairs a real change with one widget/control reload.
    @discardableResult
    static func publish(_ catalog: [WidgetAction]) -> Bool {
        guard catalog != load() else { return false }
        guard let data = EligibleActionCatalog.encode(catalog) else {
            // Unreachable today — `WidgetAction` is a plain `Codable` struct — but
            // if an encode ever failed the surfaces would silently keep the stale
            // catalog until the next successful change. Trap loudly in debug
            // (compiled out in Release, where the stale-but-rendering catalog is the
            // right degrade) rather than skip the write without a trace.
            assertionFailure("Eligible-action catalog failed to encode; the widget keeps its stale catalog")
            return false
        }
        defaults.set(data, forKey: catalogKey)
        return true
    }

    /// The current catalog — the picker's source and the join target for both render
    /// surfaces. Empty when nothing has been published or the blob is unreadable, so
    /// every configured id simply misses the join and its cell degrades to the dashed
    /// empty slot: never blank, never an error.
    static func load() -> [WidgetAction] {
        EligibleActionCatalog.decode(defaults.data(forKey: catalogKey))
    }

    /// Clears the catalog key under the `-uitest-reset-signals` launch flag (called
    /// beside `FavoritesWidgetStore.launchReset`): the key persists across UI-test
    /// runs, so a leftover catalog from a prior run would otherwise leak into a later
    /// test's assertions.
    static func launchReset() {
        defaults.removeObject(forKey: catalogKey)
    }
}
