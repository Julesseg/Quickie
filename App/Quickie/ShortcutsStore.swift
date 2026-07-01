import Foundation
import Observation
import QuickieCore

/// Owns the user's imported **Shortcut Actions** (CONTEXT.md → Shortcut Action;
/// issue #45): the `{ name, acceptsInput }` set populated *solely* by the Sync
/// Shortcut import (ADR 0007 — there is no manual add). Persisted as `Codable`
/// JSON in the shared App Group's `UserDefaults`, mirroring `FallbacksStore` /
/// `SignalsStore` so the future Share Extension and widgets read the same source
/// of truth (ADR 0006). No CloudKit — the set is small and rebuilt whole on each
/// import/edit.
///
/// The reconciliation (parse → universal auto-prune keyed by name, preserving the
/// `acceptsInput` toggle) lives in `QuickieCore.ShortcutImport` as a pure,
/// unit-tested function; this store is the thin persistence + UI-state edge.
@MainActor
@Observable
final class ShortcutsStore {
    /// The imported Shortcut Actions, in the order the last Sync Shortcut payload
    /// listed them (the re-sync rebuilds the set to mirror the payload).
    private(set) var entries: [ShortcutEntry]

    @ObservationIgnored private let defaults: UserDefaults
    private static let entriesKey = "shortcuts.entries"

    /// The published companion Sync Shortcut's own name, used to **self-filter** it
    /// out of its own `Get My Shortcuts` output (ADR 0007). Must match the name the
    /// human publishes the iCloud shortcut under (see `syncShortcutInstallURL`).
    static let syncShortcutName = "Quickie Sync"

    /// The iCloud share link the "Install Sync Shortcut" control opens (ADR 0007:
    /// distributed as an `icloud.com/shortcuts/<id>` link, not a bundled file).
    ///
    /// **HITL:** only a human can author and publish the companion Sync Shortcut in
    /// the Shortcuts app and paste its real share id here — that step can't be done
    /// from code. Until it is replaced with the published link, the Install control
    /// is disabled (see `ShortcutsView`) so the app never opens a dead URL. Publish
    /// the shortcut under the name in `syncShortcutName`, then set this to the real
    /// `https://www.icloud.com/shortcuts/<id>` link.
    static let syncShortcutInstallURL: URL? = nil

    /// The launch argument that seeds imported shortcuts under UI testing — a
    /// newline-delimited name list follows the flag (mirroring `SignalsStore`'s
    /// pin hook). It exists because XCUITest can't deliver a custom-scheme URL to
    /// the app, so this drives the *real* import path (`ingest`) to seed the set a
    /// test then asserts the Shortcuts page lists and the Result list surfaces.
    static let uitestSeedArgument = "-uitest-seed-shortcuts"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    /// The store the app launches with. Honors the shared UI-test reset flag so a
    /// test asking for a clean launcher also gets an empty Shortcut set, then
    /// optionally seeds shortcuts through the real import path (see
    /// `uitestSeedArgument`) so a test can verify listing/search without a URL.
    static func launch() -> ShortcutsStore {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(SignalsStore.uitestResetArgument) {
            SignalsStore.sharedDefaults.removeObject(forKey: entriesKey)
        }
        let store = ShortcutsStore()
        if let flag = arguments.firstIndex(of: uitestSeedArgument), flag + 1 < arguments.count {
            store.ingest(payload: arguments[flag + 1])
        }
        return store
    }

    /// Ingests a raw Sync-Shortcut payload — the whole import/re-sync round-trip:
    /// parse (split/trim/dedup/self-filter) then reconcile against the current set
    /// (universal auto-prune keyed by name, preserving each survivor's toggle), and
    /// persist. Both a first import and a re-sync are this one call.
    func ingest(payload: String) {
        let names = ShortcutImport.parse(payload, selfName: Self.syncShortcutName)
        entries = ShortcutImport.reconcile(existing: entries, names: names)
        persist()
    }

    /// Ingests the names carried by an inbound `quickie://import?names=…` URL,
    /// returning whether the URL was the import route (so the app root can tell a
    /// handled import from a URL meant for another handler). A non-import URL
    /// leaves the set untouched.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let payload = ShortcutImport.namesPayload(from: url) else { return false }
        ingest(payload: payload)
        return true
    }

    /// Flips a shortcut's "accepts input" toggle (matched by name), then persists —
    /// the only way Quickie learns a shortcut takes input, since import is
    /// names-only (CONTEXT.md → Management page).
    func toggleAcceptsInput(_ name: String) {
        guard let index = entries.firstIndex(where: { $0.name == name }) else { return }
        entries[index].acceptsInput.toggle()
        persist()
    }

    /// Removes an imported shortcut by name, then persists. (A later re-sync that
    /// still lists the name would re-add it with input off — identity is the name.)
    func delete(_ name: String) {
        entries.removeAll { $0.name == name }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.entriesKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [ShortcutEntry] {
        guard let data = defaults.data(forKey: entriesKey),
              let decoded = try? JSONDecoder().decode([ShortcutEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
