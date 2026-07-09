import Foundation
import QuickieCore
import QuickieStoreKit

/// The published snapshot of the **Bridged Action** set (CONTEXT.md → Bridged
/// Action; ADR 0024; issue #122) — the union of Favorites and Custom Actions the
/// single parameterized App Shortcut ("Run <name> with Quickie") exposes outward.
///
/// The set is *derived* in Core (`SearchEngine.bridgedActions()`), but the App
/// Intents `EntityQuery` that feeds Siri/Spotlight can run **out of process**, where
/// the in-memory engine and its `@Query`/`@AppStorage` state don't exist. So the
/// app maintains this denormalized snapshot in the shared App Group `UserDefaults`
/// (ADR 0006 — the same source of truth the Share Extension and other intents read):
/// `RootView` recomputes and `publish`es it whenever the set can change (a pin, a
/// Custom Action CRUD, a disable), and the query only ever `load`s it. Invocation
/// stays live regardless — the intent opens `quickie://run/<id>`, resolved against
/// the current catalog — so a member the snapshot still lists but the app has since
/// dropped degrades gracefully to Home (CONTEXT.md → Bridged Action).
///
/// This is the "last synced" set ADR 0024 speaks of: the snapshot is what the system
/// holds; `updateAppShortcutParameters()` is the nudge to re-read it.
enum BridgedActionStore {
    private static let key = "bridge.bridgedActions"

    /// The shared App Group defaults — the same instance every launcher store uses,
    /// so the app and any out-of-process intent read one snapshot.
    private static var defaults: UserDefaults { AppGroup.defaults }

    /// Writes the derived set as JSON, but **only when it actually changed** — an
    /// unconditional write on every keystroke-driven engine rebuild would be pure
    /// churn (and would have the caller pointlessly nudging App Shortcut parameters).
    /// Returns whether anything was written, so the caller can pair a real change with
    /// a single `updateAppShortcutParameters()`.
    @discardableResult
    static func publish(_ actions: [BridgedAction]) -> Bool {
        guard actions != load() else { return false }
        if let data = try? JSONEncoder().encode(actions) {
            defaults.set(data, forKey: key)
            return true
        }
        return false
    }

    /// The current snapshot, or `[]` when nothing has been published yet or the blob
    /// is unreadable — the query's whole source of truth.
    static func load() -> [BridgedAction] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BridgedAction].self, from: data)
        else { return [] }
        return decoded
    }
}
