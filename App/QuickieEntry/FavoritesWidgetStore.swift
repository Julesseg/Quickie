import Foundation
import QuickieCore
import QuickieStoreKit

/// The App Group keys behind the **Favorites widget projection** (ADR 0025; issue
/// #126), shared by the two processes that touch them — which is why this lives in
/// the folder synced into both the app and widget targets, like `DeeplinkInbox`:
///
/// - The **snapshot**: the app is the single writer (`publish`, rewritten whenever
///   pins or the underlying actions change); the widget only ever `load`s it to
///   render — it never opens SwiftData to draw. The same publish-only-on-change
///   posture as `BridgedActionStore`, so the caller can pair a real change with one
///   `WidgetCenter` reload.
/// - The **frecency outbox**: the widget is the writer (`recordRun`, from the copy
///   and hand-off intents); the app drains it into `SignalsStore` on foreground
///   (`drainRuns`). Frecency stays single-writer — the widget never touches
///   `SignalsStore` keys, whose whole-rewrite saves would clobber a direct write.
///
/// The codecs are Core (`FavoritesWidgetSnapshot`, `WidgetRunOutbox`) so the merge
/// grammar is `swift test`-covered; this store is only the thin keyed edge.
enum FavoritesWidgetStore {
    /// The Favorites widget's WidgetKit kind — held here, beside the snapshot the
    /// timeline renders, so the app's `reloadTimelines(ofKind:)` and the widget's
    /// configuration can never drift onto different identities.
    static let widgetKind = "QuickieFavoritesWidget"

    private static let snapshotKey = "widget.favorites"
    private static let outboxKey = "widget.pendingRuns"

    /// The shared App Group defaults — the same instance every launcher store uses,
    /// so the app's writes and the widget process's reads meet on one suite.
    private static var defaults: UserDefaults { AppGroup.defaults }

    // MARK: Snapshot — app writes, widget reads

    /// Writes the denormalized snapshot, but **only when it actually changed** —
    /// the caller recomputes it per engine rebuild, and an unconditional write
    /// would be churn plus a pointless timeline reload. Returns whether anything
    /// was written, so the caller pairs a real change with one
    /// `WidgetCenter.reloadTimelines(ofKind:)`.
    @discardableResult
    static func publish(_ favorites: [WidgetAction]) -> Bool {
        guard favorites != load() else { return false }
        guard let data = FavoritesWidgetSnapshot.encode(favorites) else {
            // Unreachable today — `WidgetAction` is a plain `Codable` struct —
            // but if an encode ever failed here the grid would silently keep its
            // stale snapshot until the next successful change, a failure that
            // reads as "the widget just didn't update". Trap loudly in debug
            // (compiled out in Release, where the stale-but-rendering grid is the
            // right degrade) rather than skip the write without a trace.
            assertionFailure("Favorites widget snapshot failed to encode; the widget keeps its stale grid")
            return false
        }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    /// The current snapshot — the widget timeline's whole source of truth. Empty
    /// when nothing has been published or the blob is unreadable, which the widget
    /// renders as the pin-invitation placeholder: never blank, never an error.
    static func load() -> [WidgetAction] {
        FavoritesWidgetSnapshot.decode(defaults.data(forKey: snapshotKey))
    }

    // MARK: Outbox — widget writes, app drains

    /// Appends a widget-run selection for the app to credit into Frecency on its
    /// next foreground. Called from the widget's copy and hand-off intents only —
    /// an open-app run lands in the app, where the ordinary tap path records its
    /// own frecency event, so outboxing it too would double-count.
    static func recordRun(actionID: String, at date: Date = Date()) {
        let event = WidgetRunEvent(actionID: actionID, date: date)
        defaults.set(WidgetRunOutbox.appending(event, to: defaults.data(forKey: outboxKey)), forKey: outboxKey)
    }

    /// Consumes the pending events, clearing the key so each run is credited once.
    /// A widget run landing between the read and the clear would be lost — a
    /// tolerable, vanishingly-narrow race for a ranking hint (`UserDefaults` has no
    /// compare-and-swap to close it), never for user content.
    static func drainRuns() -> [WidgetRunEvent] {
        let events = WidgetRunOutbox.events(from: defaults.data(forKey: outboxKey))
        if !events.isEmpty { defaults.removeObject(forKey: outboxKey) }
        return events
    }

    // MARK: UI-test seams

    /// The launch argument that seeds a pending widget-run event under UI testing —
    /// the Action id follows the flag, which may repeat. XCUITest cannot tap a
    /// Home-Screen widget, so the outbox → `SignalsStore` → Recent-list drain is
    /// otherwise undrivable; this plants a *real* outbox event before `RootView`
    /// drains it, mirroring how `-uitest-seed-frecent` seeds history directly.
    /// Pair it with `-uitest-reset-signals` so the drain lands on a clean slate.
    static let uitestSeedRunArgument = "-uitest-seed-widget-run"

    /// Clears both App Group keys under the `-uitest-reset-signals` launch flag
    /// (called from `QuickieApp.init`, beside `AppSettings.reset`): the keys
    /// persist across UI-test runs, so a leftover outbox event or snapshot from a
    /// prior run would otherwise leak into a later test's Home assertions.
    static func launchReset() {
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: outboxKey)
    }

    /// Seeds an outbox event per occurrence of `-uitest-seed-widget-run` (see
    /// `uitestSeedRunArgument`), through the real `recordRun` path. Gated on
    /// `--uitesting` by the caller so a stray flag can never write in production.
    static func seedRunsFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        for flag in arguments.indices where arguments[flag] == uitestSeedRunArgument {
            if flag + 1 < arguments.count {
                recordRun(actionID: arguments[flag + 1])
            }
        }
    }
}
