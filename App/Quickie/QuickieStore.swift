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

/// A user-saved Quicklink: a stored URL that opens directly (CONTEXT.md →
/// Quicklink, no placeholder). The skeleton persists these in SwiftData and
/// rebuilds the in-memory search index from them on launch (ADR 0006: the store
/// is the source of truth, the index is a derived cache). Snippets, Notes, and
/// placeholder-Quicklinks join the schema in later slices.
@Model
final class StoredQuicklink {
    var title: String
    var urlString: String
    var createdAt: Date

    init(title: String, urlString: String, createdAt: Date = Date()) {
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }
}

/// Owns the single `ModelContainer`, configured for the shared App Group with
/// CloudKit off for now (M1 is fully local — ADR 0006 / ROADMAP).
enum QuickieStore {
    static let container: ModelContainer = {
        let schema = Schema([StoredQuicklink.self])

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
