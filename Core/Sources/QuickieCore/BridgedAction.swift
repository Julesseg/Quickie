import Foundation

/// One member of the **Bridged Action** set (CONTEXT.md → Bridged Action; ADR 0024;
/// issue #122) — an Action exposed *outward* through the App Intents bridge as a
/// value of the single parameterized App Shortcut ("Run <name> with Quickie"). The
/// set is **derived, never hand-curated**: the union of the user's Favorites and
/// Custom Actions, minus anything Disabled (`SearchEngine.bridgedActions()`).
///
/// A `BridgedAction` carries only what the outward surface needs: the Action's
/// **stable id** — the `quickie://run/<id>` target the App Intent opens for a
/// tap-equivalent run (a Favorite runs its main action, a Custom Action starts its
/// breadcrumb) — and the **title** Siri/Spotlight show for it. It is deliberately a
/// flat value, not an `Action`: the App target's `AppEntity` mirrors these two
/// fields, and everything about *what running it does* is resolved live by the app
/// through the same id, so a stale reference (unpinned, deleted, or disabled since
/// the system last synced) simply fails to resolve and degrades to plain Home.
public struct BridgedAction: Equatable, Sendable, Identifiable, Codable {
    /// The Action's stable id — the `quickie://run/<id>` deeplink target and the
    /// `AppEntity`'s identifier, so a Siri/Spotlight invocation resolves against the
    /// live catalog exactly as a tapped result row would.
    public let id: String
    /// The display name shown for this member in Siri, Spotlight, and the Shortcuts
    /// app — the Action's own title.
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
