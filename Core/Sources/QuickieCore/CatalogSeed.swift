import Foundation

/// The **default seeds** planted on first run (CONTEXT.md → Custom Action, Catalog;
/// ADR 0023/0028/0030): the templated seeds — web search, App Store search, Wikipedia,
/// YouTube search, Google Maps — plus the three **static** site links — YouTube, Gmail,
/// GitHub (the former default Quicklinks, ADR 0030) — each an ordinary, fully deletable
/// [[Custom Action]] carrying a **fixed, well-known id** so the launch-time `StoreDedup`
/// pass can collapse the rows two devices each seed before their first CloudKit import
/// lands. The seed path is the *only* place these fixed ids are used — a manual Catalog
/// install always mints a fresh id (ADR 0028).
///
/// Pure Core data so the seed definitions, their ids, and the first-run Fallback
/// order (`FallbackActivation.firstRunEnabledIDs`) are all `swift test`-covered; the
/// App's seeding pass is a thin edge that inserts these as `StoredCustomAction`s.
public enum CatalogSeed {
    /// One default seed: its fixed `seed.*` id and the definition it plants.
    public struct Seed: Equatable, Sendable {
        public let id: String
        public let definition: CustomActionDefinition

        public init(id: String, definition: CustomActionDefinition) {
            self.id = id
            self.definition = definition
        }
    }

    public static let webSearch = Seed(
        id: "seed.web-search",
        definition: CustomActionDefinition(
            name: "Search the web",
            aliases: ["search"],
            template: "https://duckduckgo.com/?q={query}"
        )
    )

    /// App Store search (issue #144): a slotted `itms-apps` URL against the App
    /// Store's `MZSearch` endpoint — the form that opens the App Store app straight to
    /// results. A default-seeded, fully deletable Custom Action rather than a System
    /// built-in (its slotted URL fits the Custom Action model), pre-enabled as a
    /// fallback like web search and re-installable from the Catalog.
    public static let appStoreSearch = Seed(
        id: "seed.app-store-search",
        definition: CustomActionDefinition(
            name: "Search the App Store",
            aliases: ["app store"],
            template: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term={query}"
        )
    )

    public static let wikipedia = Seed(
        id: "seed.wikipedia",
        definition: CustomActionDefinition(
            name: "Wikipedia",
            aliases: ["wiki"],
            template: "https://en.wikipedia.org/wiki/Special:Search?search={query}"
        )
    )

    public static let youTube = Seed(
        id: "seed.youtube",
        definition: CustomActionDefinition(
            name: "YouTube",
            aliases: ["yt", "youtube"],
            template: "https://www.youtube.com/results?search_query={query}"
        )
    )

    public static let googleMaps = Seed(
        id: "seed.google-maps",
        definition: CustomActionDefinition(
            name: "Google Maps",
            aliases: ["maps"],
            template: "https://www.google.com/maps/search/{query}"
        )
    )

    // MARK: - Static (slot-less) seeds — the former default Quicklinks (ADR 0030)

    /// The three default **static** Custom Actions (ADR 0030): homepage-style links
    /// with **no** `{slot}`, so they open directly (the former Quicklink shape) rather
    /// than seeding a breadcrumb. They keep their original `seed.link.*` ids — the
    /// same ids the retired `StoredQuicklink` seed used — so the launch-time
    /// `StoredQuicklink` → `StoredCustomAction` migration and the fixed-id dedup line
    /// up. Unlike the templated seeds they are **not** fallback-eligible (no free-text
    /// slot to seed), so `firstRunEnabledIDs` leaves them out of the Fallback pool.
    public static let youTubeLink = Seed(
        id: "seed.link.youtube",
        definition: CustomActionDefinition(
            name: "YouTube",
            aliases: ["yt"],
            template: "https://www.youtube.com"
        )
    )

    public static let gmail = Seed(
        id: "seed.link.gmail",
        definition: CustomActionDefinition(
            name: "Gmail",
            aliases: ["mail"],
            template: "https://mail.google.com"
        )
    )

    public static let gitHubLink = Seed(
        id: "seed.link.github",
        definition: CustomActionDefinition(
            name: "GitHub",
            aliases: ["gh"],
            template: "https://github.com"
        )
    )

    /// The seeds in most-important-first order — the order the seed pass inserts them.
    /// The templated seeds come first (App Store search rides second, issue #144; the
    /// three reference seeds follow, issue #143), then the three static site links
    /// (ADR 0030). `firstRunEnabledIDs` pre-enables only the fallback-eligible
    /// (templated) seeds; the static links are ineligible by shape.
    public static let all: [Seed] = [
        webSearch, appStoreSearch, wikipedia, youTube, googleMaps,
        youTubeLink, gmail, gitHubLink,
    ]
}
