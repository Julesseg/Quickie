import Foundation

/// The **default Quicklinks** planted on first run: static, directly-opening
/// destinations (CONTEXT.md → Quicklink; ADR 0013) — YouTube, Gmail, GitHub.
/// Unlike a [[CatalogSeed]] Custom Action, a Quicklink carries **no `{placeholder}`**
/// and consumes no typed text: it is a homepage-style URL matched by name that opens
/// as-is. Each seed is an ordinary, fully deletable Quicklink under a **fixed,
/// well-known `seed.link.*` id**, so the launch-time dedup pass can collapse the two
/// rows two devices each seed before their first CloudKit import lands (the same
/// fixed-id regime the Custom Action seeds use, ADR 0023).
///
/// Pure Core data so the seed definitions and their ids are `swift test`-covered; the
/// App's seeding pass is a thin edge that inserts these as `StoredQuicklink`s.
public enum QuicklinkSeed {
    /// One default Quicklink seed: its fixed `seed.link.*` id and the static
    /// destination it plants.
    public struct Seed: Equatable, Sendable {
        public let id: String
        public let title: String
        public let urlString: String
        public let alias: String?

        public init(id: String, title: String, urlString: String, alias: String? = nil) {
            self.id = id
            self.title = title
            self.urlString = urlString
            self.alias = alias
        }
    }

    public static let youTube = Seed(
        id: "seed.link.youtube",
        title: "YouTube",
        urlString: "https://www.youtube.com",
        alias: "yt"
    )

    public static let gmail = Seed(
        id: "seed.link.gmail",
        title: "Gmail",
        urlString: "https://mail.google.com",
        alias: "mail"
    )

    public static let gitHub = Seed(
        id: "seed.link.github",
        title: "GitHub",
        urlString: "https://github.com",
        alias: "gh"
    )

    /// The seeds in most-important-first order — the order the seed pass inserts them.
    public static let all: [Seed] = [youTube, gmail, gitHub]
}
