import Foundation
import SwiftData

/// The shared App Group that backs Quickie's store. Decided up front (ADR 0006)
/// so the future Share Extension, widgets, and App Intents write to the same
/// source of truth as the app — moving the store into an App Group later is a
/// painful migration.
///
/// NOTE: this identifier must match the `com.apple.security.application-groups`
/// entry in `Quickie.entitlements`, and the App Group must be enabled for the
/// app's bundle ID in your Apple Developer account.
enum AppGroup {
    static let identifier = "group.com.julesseguin.quickie"
}

/// A user-saved Quicklink: a stored URL *template* with zero or more
/// `{placeholder}` tokens (CONTEXT.md → Quicklink). With no placeholder it opens
/// directly; with one it takes the typed text as its Argument. The skeleton
/// persists these in SwiftData and rebuilds the in-memory search index from them
/// on launch (ADR 0006: the store is the source of truth, the index is a derived
/// cache). Snippets and Notes join the schema in later slices.
///
/// `alias` and `isFallback` are additive (issue #5): optional / defaulted so
/// SwiftData migrates existing stores automatically. `urlString` holds the URL
/// template; a placeholder-Quicklink flagged `isFallback` always rides in the
/// bottom fallback region, consuming the raw typed text.
@Model
final class StoredQuicklink {
    var title: String
    var urlString: String
    /// An optional alternative name also matched against the query.
    var alias: String?
    /// When true, this placeholder-Quicklink is pinned as a Fallback row.
    var isFallback: Bool = false
    var createdAt: Date

    init(
        title: String,
        urlString: String,
        alias: String? = nil,
        isFallback: Bool = false,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.urlString = urlString
        self.alias = alias
        self.isFallback = isFallback
        self.createdAt = createdAt
    }
}

/// A user-saved Snippet: reusable text whose main action is **Copy**
/// (CONTEXT.md → Snippet) — canned replies, an address, a template pasted
/// repeatedly. Persisted in SwiftData alongside Quicklinks; the in-memory index
/// is rebuilt from these on launch (ADR 0006). A Snippet shares storage with a
/// future Note but is distinct in intent: copy-out, not read.
@Model
final class StoredSnippet {
    var title: String
    var body: String
    var createdAt: Date

    init(title: String, body: String, createdAt: Date = Date()) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

/// Owns the single `ModelContainer`, configured for the shared App Group with
/// CloudKit off for now (M1 is fully local — ADR 0006 / ROADMAP).
enum QuickieStore {
    static let container: ModelContainer = {
        let schema = Schema([StoredQuicklink.self, StoredSnippet.self])

        // Only ask SwiftData for the shared App Group container when this build
        // is actually entitled for it — `containerURL(forSecurityApplication…)`
        // returns nil otherwise. Probing first avoids constructing a grouped
        // ModelConfiguration that would stall or error on a device/CI simulator
        // where the App Group capability isn't provisioned (ADR 0012: never
        // block the input). When the group is unavailable we degrade to a plain
        // local store; data simply isn't shared with extensions until the group
        // is configured (ADR 0006).
        let appGroupAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil

        let configuration = appGroupAvailable
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier), cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create Quickie ModelContainer: \(error)")
        }
    }()
}
