import Foundation
import Observation
import QuickieCore

/// Owns the user's ranking signals — pinned **Favorites** and the **Frecency**
/// of past selections (CONTEXT.md → Favorite, Frecency; issue #9) — and persists
/// them so they survive launches. Both feed `SearchEngine`: the App rebuilds the
/// engine from this store on every keystroke, and records a frecency event on
/// every main-action tap.
///
/// Stored in the shared App Group's `UserDefaults` (ADR 0006: the future Share
/// Extension and widgets read the same source of truth). Small, structured, and
/// rewritten whole on each change — no CloudKit yet (M1 is local). Favorites are
/// an ordered list (pin order is what Home renders); Frecency is `Codable`, so
/// it round-trips as JSON.
@MainActor
@Observable
final class SignalsStore {
    /// Pinned Favorites in pin order — the order Home renders the row in.
    private(set) var favorites: [String]
    /// The frequency × recency record of past selections.
    private(set) var frecency: Frecency

    @ObservationIgnored private let defaults: UserDefaults
    private static let favoritesKey = "signals.favorites"
    private static let frecencyKey = "signals.frecency"

    /// The launch argument that resets persisted launcher signals to a clean
    /// slate under UI testing. Shared so every store that honors it names the same
    /// flag — note its reach is broad: it clears Favorites/Frecency **and** the
    /// Fallback list order/disabled set (see `FallbacksStore.launch`), so a test
    /// that passes it gets a fully reset launcher, not just reset Favorites.
    static let uitestResetArgument = "-uitest-reset-signals"

    /// The launch argument that pre-pins a Favorite under UI testing — the Action
    /// id to pin follows the flag. It exists because XCUITest cannot fire a SwiftUI
    /// **context-menu** item's action in the iOS simulator (the menu is a separate
    /// remote view; the tap is synthesized but the action never runs), even though
    /// the long-press pin works on device. This seeds a pinned Favorite through the
    /// real `toggleFavorite` path so a test can verify Home renders it, without
    /// driving the undrivable gesture. Pair it with `-uitest-reset-signals` so the
    /// pin lands on a clean slate.
    static let uitestPinArgument = "-uitest-pin-favorite"

    /// The launch argument that seeds a Frecency entry under UI testing — the
    /// Action id to record follows the flag, and the flag may repeat to seed
    /// several entries. It exists because Home's Recent list only renders when
    /// there is frecency history, which a UI test could otherwise build only by
    /// tapping rows first — extra steps that couple the test to unrelated
    /// behavior (issue #71). This seeds history through the real
    /// `SignalsStore.record` path, mirroring how `uitestPinArgument` seeds a
    /// Favorite. Pair it with `-uitest-reset-signals` so the seeded entries land
    /// on a clean slate.
    static let uitestSeedFrecentArgument = "-uitest-seed-frecent"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        self.favorites = defaults.stringArray(forKey: Self.favoritesKey) ?? []
        self.frecency = Self.loadFrecency(from: defaults)
    }

    /// The store the app launches with. Under UI tests it starts from a clean
    /// slate (the `-uitest-reset-signals` launch argument) so persisted Favorites
    /// and Frecency from a prior run can't leak across tests — without it, one
    /// test tapping a row would record frecency that a later "empty Home"
    /// assertion would then trip over.
    static func launch() -> SignalsStore {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(uitestResetArgument) {
            let defaults = sharedDefaults
            defaults.removeObject(forKey: favoritesKey)
            defaults.removeObject(forKey: frecencyKey)
        }
        let store = SignalsStore()
        // UI-test hook: pre-pin the Favorite whose Action id follows the flag (see
        // `uitestPinArgument`), through the real toggle path, so a test can assert
        // Home renders a pinned Favorite without the undrivable context menu.
        if let flag = arguments.firstIndex(of: uitestPinArgument), flag + 1 < arguments.count {
            store.toggleFavorite(arguments[flag + 1])
        }
        // UI-test hook: seed a Frecency entry per occurrence of the flag (see
        // `uitestSeedFrecentArgument`), through the real record path, so a test
        // can drive Home's Recent list without tapping rows to build history.
        for flag in arguments.indices where arguments[flag] == uitestSeedFrecentArgument {
            if flag + 1 < arguments.count {
                store.record(arguments[flag + 1])
            }
        }
        return store
    }

    /// Whether `id` is currently pinned — drives the Pin/Unpin affordance.
    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    /// The Favorites cap (CONTEXT.md → Favorite): the 2×2 grid holds at most four,
    /// so a fifth pin is refused until one is unpinned.
    static let maxFavorites = 4

    /// Pins an unpinned Action (appending to the end) or unpins a pinned one
    /// (issue #9 AC #1), then persists. Pinning a fifth Favorite is **refused** —
    /// the grid is capped at four (CONTEXT.md → Favorite) — leaving the list
    /// unchanged until the user unpins one.
    func toggleFavorite(_ id: String) {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
        } else {
            guard favorites.count < Self.maxFavorites else { return }
            favorites.append(id)
        }
        defaults.set(favorites, forKey: Self.favoritesKey)
    }

    /// Whether `id` can be pinned right now — false once the cap is reached (and
    /// the Action isn't already pinned). Lets the UI explain a refused fifth pin
    /// rather than silently ignoring the gesture.
    func canFavorite(_ id: String) -> Bool {
        isFavorite(id) || favorites.count < Self.maxFavorites
    }

    /// Drops any pinned Favorite whose Action can no longer be resolved from the
    /// live catalog — its target was deleted, or it was pinned under an id that an
    /// older build derived from an unstable `persistentModelID.hashValue`. Without
    /// this an unresolvable Favorite draws no card yet still occupies one of the
    /// four slots, so the user hits the cap "early" with an invisible pin they
    /// can't see to unpin. Persists only when something actually changed.
    func reconcileFavorites(against resolvableIDs: Set<String>) {
        let kept = favorites.filter { resolvableIDs.contains($0) }
        guard kept.count != favorites.count else { return }
        favorites = kept
        defaults.set(favorites, forKey: Self.favoritesKey)
    }

    /// Records that the user selected `id` now (issue #9 AC #2), then persists.
    func record(_ id: String, at date: Date = Date()) {
        frecency.record(id, at: date)
        if let data = try? JSONEncoder().encode(frecency) {
            defaults.set(data, forKey: Self.frecencyKey)
        }
    }

    private static func loadFrecency(from defaults: UserDefaults) -> Frecency {
        guard let data = defaults.data(forKey: frecencyKey),
              let decoded = try? JSONDecoder().decode(Frecency.self, from: data)
        else { return Frecency() }
        return decoded
    }

    /// The App Group `UserDefaults`, falling back to `.standard` when the group
    /// isn't provisioned — the same degrade-gracefully posture as the SwiftData
    /// store (QuickieStore), so signals work on an unentitled build too.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }
}
