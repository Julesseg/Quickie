import Foundation
import Observation
import QuickieCore

/// Builds and holds the **File Search snapshot** (CONTEXT.md → File Search; ADR
/// 0015) — the plain, in-memory `FilenameIndex` the pure `FileSearchProvider`
/// matches every keystroke against, so the Core never rescans the filesystem while
/// the user types.
///
/// The build pass is the only place the filesystem is touched. Because iOS caps
/// simultaneously-open security-scoped resources, it brackets
/// `start`/`stopAccessingSecurityScopedResource()` **per folder** — one grant open
/// at a time — walking each Indexed Folder recursively for **filenames only** and
/// recording each as a pure `FileEntry` `(bookmarkID, relativePath, displayName)`.
/// The snapshot rebuilds on **launch, foreground, and Indexed-Folder grant
/// change** (see `RootView`); live filesystem watching is deferred (it fights the
/// resource-limit constraint).
///
/// The walk runs off the main actor so a large folder never stalls typing; its
/// result is published back on the main actor as a fresh snapshot — but only when
/// it differs from the current one, so the routine relaunch/foreground rebuilds
/// don't invalidate observers with an identical index (#112). A newer rebuild
/// cancels an in-flight one so rapid grant edits settle on the latest state.
@MainActor
@Observable
final class FileIndexModel {
    /// The current snapshot. Starts empty (no granted folders yet) and is replaced
    /// wholesale by each completed build pass.
    private(set) var index = FilenameIndex(entries: [])

    /// The in-flight build, retained so a newer rebuild can cancel it — the last
    /// rebuild wins rather than an older, slower walk clobbering a newer snapshot.
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?

    /// Rebuilds the snapshot from the user's current grants. Resolves each
    /// bookmark to a URL on the main actor (the store is main-actor isolated), then
    /// walks them off-actor under a per-folder security-scoped bracket and swaps in
    /// the fresh snapshot when done. A grant whose bookmark no longer resolves is
    /// simply skipped — the store prunes dead grants on its own.
    func rebuild(from store: IndexedFoldersStore) {
        let targets: [(bookmarkID: String, url: URL)] = store.grants.compactMap { grant in
            guard let url = store.resolveURL(for: grant) else { return nil }
            return (grant.id, url)
        }

        rebuildTask?.cancel()
        rebuildTask = Task.detached(priority: .utility) {
            let entries = Self.buildEntries(from: targets)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Publish only when the walk actually found something different.
                // Every foreground return triggers a rebuild (see RootView), and
                // this write lands from a detached task at an unpredictable point
                // in the scene transition — replacing the snapshot with an equal
                // one invalidates every observer for nothing, the launch-race
                // amplifier behind the DisplayList crash in #112.
                guard entries != self.index.entries else { return }
                self.index = FilenameIndex(entries: entries)
            }
        }
    }

    /// Walks every target folder under its own start/stop bracket and flattens the
    /// results into one entry list. Bracketing **per folder** (not around the whole
    /// pass) keeps at most one security-scoped resource open at a time, respecting
    /// the iOS limit.
    private nonisolated static func buildEntries(from targets: [(bookmarkID: String, url: URL)]) -> [FileEntry] {
        var entries: [FileEntry] = []
        for target in targets {
            if Task.isCancelled { break }
            let scoped = target.url.startAccessingSecurityScopedResource()
            defer { if scoped { target.url.stopAccessingSecurityScopedResource() } }
            entries.append(contentsOf: walk(root: target.url, bookmarkID: target.bookmarkID))
        }
        return entries
    }

    /// Recursively enumerates a granted folder for **filenames only** (directories,
    /// hidden files, and package internals are skipped), recording each regular
    /// file as a pure `FileEntry` whose `relativePath` is taken relative to the
    /// folder's root. The caller holds the security-scoped bracket.
    private nonisolated static func walk(root: URL, bookmarkID: String) -> [FileEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootPath = root.standardizedFileURL.path
        var entries: [FileEntry] = []
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            entries.append(FileEntry(
                bookmarkID: bookmarkID,
                relativePath: relativePath(of: fileURL, underRootPath: rootPath),
                displayName: fileURL.lastPathComponent
            ))
        }
        return entries
    }

    /// A file's path relative to its Indexed Folder's root (e.g. `docs/report.pdf`),
    /// falling back to the bare filename if the URL somehow sits outside the root.
    private nonisolated static func relativePath(of fileURL: URL, underRootPath rootPath: String) -> String {
        let full = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if full.hasPrefix(prefix) {
            return String(full.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }
}
