import Foundation
import QuickieCore
import QuickieStoreKit

/// The App Group key behind the **Pending query** snapshot (CONTEXT.md →
/// Pending query; issue #152; ADR 0031): the app writes `PendingQuery` here on
/// backgrounding and consumes it at the next activation — warm foreground or
/// cold launch — deciding restore-vs-commit by comparing timestamps. Living in
/// the App Group (rather than in-process state) is what makes termination lose
/// nothing: a cold launch reads the same snapshot a warm resume would have.
/// The codec is Core (`PendingQuery.encoded`/`decode`) so the grammar is
/// `swift test`-covered; this store is only the thin keyed edge.
enum PendingQueryStore {
    private static let key = "pile.pendingQuery"

    /// The shared App Group defaults — the same suite every launcher store uses.
    private static var defaults: UserDefaults { AppGroup.defaults }

    /// Persists the background-time snapshot. Nothing to encode is unreachable
    /// today (`PendingQuery` is a plain `Codable` struct); a failure degrades to
    /// "nothing pending", which restores nothing but also destroys nothing —
    /// the warm resume still has the live `query`.
    static func save(_ pending: PendingQuery) {
        guard let data = pending.encoded() else { return }
        defaults.set(data, forKey: key)
    }

    /// Consumes the pending snapshot, clearing the key so each backgrounding is
    /// resolved exactly once — activation and an entry-surface deeplink can both
    /// race for it, and whichever reads first wins.
    static func take() -> PendingQuery? {
        guard let pending = PendingQuery.decode(defaults.data(forKey: key)) else { return nil }
        defaults.removeObject(forKey: key)
        return pending
    }

    // MARK: UI-test seams

    /// Clears the key under the `-uitest-reset-signals` launch flag (called from
    /// `QuickieApp.init` beside the other App Group resets): the snapshot
    /// persists across UI-test runs, so a leftover pending query from a prior
    /// run would otherwise restore or commit into a later test's clean launch.
    static func launchReset() {
        defaults.removeObject(forKey: key)
    }

    /// The launch arguments that seed a pending snapshot under UI testing:
    /// `-uitest-seed-pending <text>` plus `-uitest-pending-age <seconds>`.
    /// XCUITest cannot control the wall clock across a backgrounding, so a test
    /// plants a *real* snapshot with a chosen age before `RootView` resolves it
    /// on first activation — driving both the restore (< 30s) and the commit
    /// (≥ 30s) cold-launch paths without a 30-second wait.
    static let uitestSeedTextArgument = "-uitest-seed-pending"
    static let uitestSeedAgeArgument = "-uitest-pending-age"

    /// Seeds the snapshot from the launch arguments above, through the real
    /// `save` path. Gated on `--uitesting` by the caller so a stray flag can
    /// never write in production.
    static func seedFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let textFlag = arguments.firstIndex(of: uitestSeedTextArgument),
              textFlag + 1 < arguments.count else { return }
        var age: TimeInterval = 0
        if let ageFlag = arguments.firstIndex(of: uitestSeedAgeArgument),
           ageFlag + 1 < arguments.count,
           let seconds = TimeInterval(arguments[ageFlag + 1]) {
            age = seconds
        }
        save(PendingQuery(text: arguments[textFlag + 1], backgroundedAt: Date().addingTimeInterval(-age)))
    }
}
