import Foundation

/// One filename in an Indexed Folder, as File Search sees it (CONTEXT.md → File
/// Search; ADR 0015). It carries **only** identity, never a filesystem URL: the
/// owning folder's security-scoped `bookmarkID`, the file's `relativePath` within
/// that folder, and the `displayName` matched against the query. The app resolves
/// `(bookmarkID, relativePath)` back to a URL under a start/stop bracket when the
/// user opens the row — the Core stays pure.
public struct FileEntry: Equatable, Sendable {
    /// The Indexed-Folder grant this file lives under — the app's key back to a
    /// security-scoped bookmark.
    public let bookmarkID: String
    /// The file's path relative to its Indexed Folder's root.
    public let relativePath: String
    /// The name shown in the row and matched against the query — the filename.
    public let displayName: String

    /// Builds an entry, defaulting the display name to the relative path's last
    /// component so the common case (match on the filename) needs no extra field.
    public init(bookmarkID: String, relativePath: String, displayName: String? = nil) {
        self.bookmarkID = bookmarkID
        self.relativePath = relativePath
        self.displayName = displayName ?? (relativePath as NSString).lastPathComponent
    }
}

/// The pure, in-memory **snapshot** File Search fuzzy-matches against (CONTEXT.md
/// → File Search; ADR 0015). Because iOS caps simultaneously-open security-scoped
/// resources, the app builds this by bracketing access per folder during a build
/// pass and materializes a plain list of entries here; every keystroke is then
/// served from the snapshot, never by rescanning the filesystem. Rebuilt on
/// launch, foreground, and Indexed-Folder grant change.
public struct FilenameIndex: Sendable {
    /// The materialized filenames — the whole searchable set.
    public let entries: [FileEntry]

    public init(entries: [FileEntry]) {
        self.entries = entries
    }

    /// The entries worth scoring for `query`: a cheap, **sound** trigram gate
    /// (`Matcher.passesTrigramPrefilter`) that skips candidates that can't be a
    /// near-match, so the expensive edit-distance pass runs over a handful rather
    /// than the whole index. It never drops a candidate the full matcher would
    /// accept; for very short queries the gate can't reject soundly, so it passes
    /// everything and defers to scoring.
    public func prefiltered(for query: String) -> [FileEntry] {
        entries.filter { Matcher.passesTrigramPrefilter(query, $0.displayName) }
    }
}
