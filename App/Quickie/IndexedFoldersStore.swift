import Foundation
import Observation

/// A single **Indexed Folder** grant (CONTEXT.md → Indexed Folder; issue #49): a
/// folder the user has explicitly allowed Quickie to search, captured as an opaque
/// **security-scoped bookmark** plus a display name for the list.
///
/// The bookmark is device-specific and opaque, which is exactly why grants are
/// stored device-locally and never synced (ADR 0016) — a bookmark minted on one
/// device is meaningless on another.
struct IndexedFolderGrant: Identifiable, Equatable {
    /// A stable identity assigned at grant time, so a row survives relaunch and a
    /// removal targets exactly one grant.
    let id: String
    /// The folder's last path component, shown in the list — the bookmark itself
    /// is opaque and unreadable.
    let displayName: String
    /// The opaque security-scoped bookmark the app resolves back to a URL.
    let bookmark: Data
}

/// Owns the user's **Indexed Folder** grants (CONTEXT.md → Indexed Folder; issue
/// #49): grant a folder, list the grants, revoke one. No searching yet — this is
/// the access foundation the future File Search Provider will read.
///
/// Grants persist as security-scoped bookmarks in a **device-local, non-synced**
/// JSON file in the shared App-Group container (ADR 0016). They are deliberately
/// kept out of the CloudKit-syncable SwiftData store: the bookmarks are opaque and
/// device-specific, so syncing them would carry dead references between devices.
///
/// On load every bookmark is resolved; a grant whose bookmark no longer resolves
/// (the folder was deleted or moved beyond recovery) is **pruned** rather than left
/// as a dead row — the resolve-with-staleness contract the acceptance criteria pin.
@MainActor
@Observable
final class IndexedFoldersStore {
    /// The live grants, most-recent-last, already pruned of anything that failed to
    /// resolve on load.
    private(set) var grants: [IndexedFolderGrant]

    @ObservationIgnored private let fileURL: URL

    /// Builds a store backed by a device-local file. Under UI testing a fresh
    /// unique file is used so each run starts empty and never inherits grants from a
    /// previous run — mirroring the in-memory SwiftData store.
    static func launch() -> IndexedFoldersStore {
        IndexedFoldersStore(fileURL: Self.storeURL())
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.grants = []
        loadAndPrune()
    }

    /// Grants access to `url`, minting a security-scoped bookmark and persisting it.
    /// The picked URL arrives already security-scoped from the document picker, so we
    /// balance a `start`/`stop` around bookmark creation. A folder already granted
    /// (same resolved path) is a no-op, so re-adding never duplicates a row.
    @discardableResult
    func addFolder(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? url.bookmarkData() else { return false }

        // De-dupe by resolved path so the same folder can't be granted twice.
        if grants.contains(where: { resolveURL(for: $0)?.standardizedFileURL == url.standardizedFileURL }) {
            return false
        }

        let grant = IndexedFolderGrant(
            id: UUID().uuidString,
            displayName: url.lastPathComponent,
            bookmark: bookmark
        )
        grants.append(grant)
        persist()
        return true
    }

    /// Revokes a grant: drops it from the list so the folder is no longer
    /// searchable, discarding its bookmark. Persisted immediately.
    func remove(_ id: String) {
        grants.removeAll { $0.id == id }
        persist()
    }

    /// Resolves a grant's bookmark to a security-scoped URL, or `nil` if it no longer
    /// resolves. Callers that then *read* the folder must balance a
    /// `startAccessingSecurityScopedResource()` around their access; this method only
    /// resolves the URL (used here for de-dupe and load-time pruning).
    func resolveURL(for grant: IndexedFolderGrant) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: grant.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return url
    }

    // MARK: - Persistence (device-local, never synced — ADR 0016)

    private struct PersistedGrant: Codable {
        let id: String
        let displayName: String
        let bookmark: Data
    }

    /// Loads the persisted grants and prunes any whose bookmark no longer resolves,
    /// rewriting the file when something was dropped so a dead grant never lingers.
    private func loadAndPrune() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([PersistedGrant].self, from: data) else {
            grants = []
            return
        }
        let loaded = stored.map { IndexedFolderGrant(id: $0.id, displayName: $0.displayName, bookmark: $0.bookmark) }
        let resolvable = loaded.filter { resolveURL(for: $0) != nil }
        grants = resolvable
        if resolvable.count != loaded.count { persist() }
    }

    private func persist() {
        let stored = grants.map { PersistedGrant(id: $0.id, displayName: $0.displayName, bookmark: $0.bookmark) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The reset launch argument: under UI testing it clears the store file before
    /// load, so a test that wants a clean slate starts empty, while a *relaunch*
    /// without it keeps the fixed test file — the seam that lets a UI test prove a
    /// grant survives relaunch.
    static let uitestResetArgument = "-uitest-reset-folders"

    /// The device-local store file, in the App-Group container when entitled (so a
    /// future extension reads the same grants) and the app's own Application Support
    /// otherwise. Deliberately a plain file, not the CloudKit-syncable SwiftData
    /// store — grants must stay per-device (ADR 0016). Under UI testing a fixed file
    /// name is used (so relaunch-persistence is testable), cleared on the reset arg.
    private static func storeURL() -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        let name = arguments.contains("--uitesting") ? "indexed-folders-uitest.json" : "indexed-folders.json"

        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent(name)
        if arguments.contains(uitestResetArgument) {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

extension IndexedFoldersStore {
    /// A UI-testing seam: grant a freshly created temporary folder without driving
    /// the system document picker (which can't be automated in CI). Lets the
    /// XCUITest exercise add → list → remove and relaunch-persistence against a real
    /// resolvable bookmark. No-op outside UI testing.
    @discardableResult
    func addTemporaryFolderForTesting() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return false }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Indexed-\(UUID().uuidString.prefix(6))", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            return false
        }
        return addFolder(dir)
    }
}
