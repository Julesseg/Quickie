import Foundation

/// The built-in, read-only **Catalog** (CONTEXT.md → Catalog; ADR 0028): a gallery
/// of ready-made [[Custom Action]] templates, grouped by category, that a user can
/// **install** with one tap from the Custom Actions Management page's "Browse
/// catalog" row. Pure data in `QuickieCore` so `swift test` validates every shipped
/// template up front — it parses and is schemed (the same Custom Action Save gates)
/// — and unverifiable templates are dropped from the data rather than shipped broken.
/// A template carries **zero or more** slots (ADR 0030): the "Sites" section holds
/// slot-less static links (the former Quicklinks), every other section is templated.
///
/// Installing an entry stamps out an *ordinary* Custom Action under a **fresh id**
/// (ADR 0028): no installed-state, no link back, no overwrite path. Every entry
/// always offers Install, and restoring a deleted action is simply installing again.
/// The first-run **default seeds** (`CatalogSeed`) are the one exception that carries
/// fixed ids — that is the seed path's doing (ADR 0023 dedup), not the Catalog's — and
/// they appear here too, listed for re-install (the static site seeds under "Sites").
public enum CatalogCategory: String, CaseIterable, Sendable {
    case searchEngines
    case aiChats
    case reference
    case appCaptures
    case communication
    /// **Sites** (ADR 0030): static homepage links with no `{slot}` — the former
    /// Quicklinks. Installing one stamps out a slot-less Custom Action that opens the
    /// URL directly. Kept a distinct section so a static site (e.g. YouTube's homepage)
    /// reads apart from the *search* entry of the same name in "Reference & site search".
    case sites

    /// The section header shown on the Catalog page, in `allCases` order.
    public var title: String {
        switch self {
        case .searchEngines: return "Search engines"
        case .aiChats: return "AI chats"
        case .reference: return "Reference & site search"
        case .appCaptures: return "App captures"
        case .communication: return "Communication & utilities"
        case .sites: return "Sites"
        }
    }
}

/// One ready-made Catalog template. `id` is a stable slug used for identity within
/// the Catalog (tests, list diffing) — **not** the id the installed Custom Action
/// gets, which is always freshly minted (ADR 0028). `requiresApp`, when set, is the
/// name shown in the "Requires <app>" note for an app-scheme entry.
public struct CatalogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let category: CatalogCategory
    public let template: String
    public let requiresApp: String?
    public let argumentSpecs: [String: ArgumentSpec]

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        category: CatalogCategory,
        template: String,
        requiresApp: String? = nil,
        argumentSpecs: [String: ArgumentSpec] = [:]
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.template = template
        self.requiresApp = requiresApp
        self.argumentSpecs = argumentSpecs
    }

    /// The `CustomActionDefinition` this entry installs — the exact value the create
    /// path persists, so an installed copy is indistinguishable from a hand-made one.
    public var definition: CustomActionDefinition {
        CustomActionDefinition(
            name: name,
            aliases: aliases,
            template: template,
            argumentSpecs: argumentSpecs
        )
    }
}

public enum Catalog {
    /// A `number`-typed slot spec — used by the phone-number templates so the
    /// breadcrumb raises the numeric keyboard.
    private static let number = ["number": ArgumentSpec(type: .number)]

    /// Every shipped Catalog entry, in category then within-category order. Kept flat
    /// so `swift test` can validate the whole set; the page groups it by `category`.
    ///
    /// **Verify-or-drop (v1):** a prefill URL that doesn't work in practice is cut,
    /// not shipped broken. Messenger and Signal (shaky share schemes) are dropped from
    /// the communication set per the ticket, and any future unverifiable template is
    /// dropped here rather than degraded.
    public static let entries: [CatalogEntry] = [
        // Search engines
        CatalogEntry(id: "catalog.google", name: "Google", aliases: ["google"], category: .searchEngines,
                     template: "https://www.google.com/search?q={query}"),
        CatalogEntry(id: "catalog.duckduckgo", name: "DuckDuckGo", aliases: ["ddg"], category: .searchEngines,
                     template: "https://duckduckgo.com/?q={query}"),
        CatalogEntry(id: "catalog.bing", name: "Bing", aliases: ["bing"], category: .searchEngines,
                     template: "https://www.bing.com/search?q={query}"),
        CatalogEntry(id: "catalog.kagi", name: "Kagi", aliases: ["kagi"], category: .searchEngines,
                     template: "https://kagi.com/search?q={query}"),
        CatalogEntry(id: "catalog.ecosia", name: "Ecosia", aliases: ["ecosia"], category: .searchEngines,
                     template: "https://www.ecosia.org/search?q={query}"),
        CatalogEntry(id: "catalog.brave", name: "Brave Search", aliases: ["brave"], category: .searchEngines,
                     template: "https://search.brave.com/search?q={query}"),
        CatalogEntry(id: "catalog.startpage", name: "Startpage", aliases: ["startpage"], category: .searchEngines,
                     template: "https://www.startpage.com/sp/search?query={query}"),

        // AI chats
        CatalogEntry(id: "catalog.chatgpt", name: "ChatGPT", aliases: ["gpt", "chatgpt"], category: .aiChats,
                     template: "https://chatgpt.com/?q={prompt}"),
        CatalogEntry(id: "catalog.claude", name: "Claude", aliases: ["claude"], category: .aiChats,
                     template: "https://claude.ai/new?q={prompt}"),
        CatalogEntry(id: "catalog.perplexity", name: "Perplexity", aliases: ["perplexity"], category: .aiChats,
                     template: "https://www.perplexity.ai/search?q={query}"),

        // Reference & site search. The three non-web seeds are listed here for
        // re-install (CONTEXT.md → Catalog); their name/aliases/template are pulled
        // straight from `CatalogSeed` so the two can never drift — the re-install copy
        // is the seed, verbatim, under the seed's own fixed id.
        seedEntry(CatalogSeed.wikipedia, in: .reference),
        seedEntry(CatalogSeed.youTube, in: .reference),
        seedEntry(CatalogSeed.googleMaps, in: .reference),
        seedEntry(CatalogSeed.appStoreSearch, in: .reference),
        CatalogEntry(id: "catalog.amazon", name: "Amazon", aliases: ["amazon"], category: .reference,
                     template: "https://www.amazon.com/s?k={query}"),
        CatalogEntry(id: "catalog.reddit", name: "Reddit", aliases: ["reddit"], category: .reference,
                     template: "https://www.reddit.com/search/?q={query}"),
        CatalogEntry(id: "catalog.github", name: "GitHub", aliases: ["github", "gh"], category: .reference,
                     template: "https://github.com/search?q={query}"),
        CatalogEntry(id: "catalog.stackoverflow", name: "Stack Overflow", aliases: ["so", "stackoverflow"], category: .reference,
                     template: "https://stackoverflow.com/search?q={query}"),
        CatalogEntry(id: "catalog.imdb", name: "IMDb", aliases: ["imdb"], category: .reference,
                     template: "https://www.imdb.com/find/?q={query}"),
        CatalogEntry(id: "catalog.wolfram", name: "Wolfram Alpha", aliases: ["wolfram"], category: .reference,
                     template: "https://www.wolframalpha.com/input?i={query}"),
        CatalogEntry(id: "catalog.google-translate", name: "Google Translate", aliases: ["translate"], category: .reference,
                     template: "https://translate.google.com/?sl=auto&tl=en&text={text}"),
        CatalogEntry(id: "catalog.deepl", name: "DeepL", aliases: ["deepl"], category: .reference,
                     template: "https://www.deepl.com/translator#auto/en/{text}"),
        CatalogEntry(id: "catalog.merriam-webster", name: "Merriam-Webster", aliases: ["dictionary", "define"], category: .reference,
                     template: "https://www.merriam-webster.com/dictionary/{word}"),

        // App captures
        CatalogEntry(id: "catalog.things", name: "Things", aliases: ["things"], category: .appCaptures,
                     template: "things:///add?title={title}&notes={notes}", requiresApp: "Things"),
        CatalogEntry(id: "catalog.todoist", name: "Todoist", aliases: ["todoist"], category: .appCaptures,
                     template: "todoist://addtask?content={content}", requiresApp: "Todoist"),
        CatalogEntry(id: "catalog.omnifocus", name: "OmniFocus", aliases: ["omnifocus"], category: .appCaptures,
                     template: "omnifocus:///add?name={name}&note={note}", requiresApp: "OmniFocus"),
        CatalogEntry(id: "catalog.bear", name: "Bear", aliases: ["bear"], category: .appCaptures,
                     template: "bear://x-callback-url/create?title={title}&text={text}", requiresApp: "Bear"),
        CatalogEntry(id: "catalog.drafts", name: "Drafts", aliases: ["drafts"], category: .appCaptures,
                     template: "drafts://x-callback-url/create?text={text}", requiresApp: "Drafts"),
        CatalogEntry(id: "catalog.obsidian", name: "Obsidian", aliases: ["obsidian"], category: .appCaptures,
                     template: "obsidian://new?name={name}&content={content}", requiresApp: "Obsidian"),
        CatalogEntry(id: "catalog.dayone", name: "Day One", aliases: ["dayone", "journal"], category: .appCaptures,
                     template: "dayone://post?entry={entry}", requiresApp: "Day One"),
        CatalogEntry(id: "catalog.fantastical", name: "Fantastical", aliases: ["fantastical"], category: .appCaptures,
                     template: "x-fantastical3://parse?sentence={sentence}", requiresApp: "Fantastical"),
        CatalogEntry(id: "catalog.google-calendar", name: "Google Calendar", aliases: ["gcal", "calendar"], category: .appCaptures,
                     template: "https://calendar.google.com/calendar/render?action=TEMPLATE&text={title}"),

        // Communication & utilities
        CatalogEntry(id: "catalog.email", name: "Email compose", aliases: ["email", "mail"], category: .communication,
                     template: "mailto:{to}?subject={subject}&body={body}"),
        CatalogEntry(id: "catalog.sms", name: "Text a number", aliases: ["sms", "text"], category: .communication,
                     template: "sms:{number}&body={message}", argumentSpecs: number),
        CatalogEntry(id: "catalog.tel", name: "Call a number", aliases: ["call", "phone"], category: .communication,
                     template: "tel:{number}", argumentSpecs: number),
        CatalogEntry(id: "catalog.whatsapp", name: "WhatsApp", aliases: ["whatsapp"], category: .communication,
                     template: "https://wa.me/?text={text}"),
        CatalogEntry(id: "catalog.telegram", name: "Telegram share", aliases: ["telegram"], category: .communication,
                     template: "https://t.me/share/url?url={url}"),
        CatalogEntry(id: "catalog.spotify", name: "Spotify search", aliases: ["spotify"], category: .communication,
                     template: "https://open.spotify.com/search/{query}"),
        CatalogEntry(id: "catalog.apple-music", name: "Apple Music search", aliases: ["apple music", "music"], category: .communication,
                     template: "https://music.apple.com/search?term={term}"),
        CatalogEntry(id: "catalog.17track", name: "17track package tracking", aliases: ["17track", "track"], category: .communication,
                     template: "https://t.17track.net/en#nums={tracking}"),
        CatalogEntry(id: "catalog.waze", name: "Waze", aliases: ["waze"], category: .communication,
                     template: "https://waze.com/ul?q={query}"),

        // Sites — static, slot-less homepage links (ADR 0030). The three default site
        // seeds are listed here for re-install, pulled straight from `CatalogSeed` so
        // they can never drift from what the seed pass plants; the rest are ordinary
        // fresh-id installs. Chosen to avoid name collisions with the *search* entries
        // above (e.g. this is YouTube's homepage, not the YouTube search).
        seedEntry(CatalogSeed.youTubeLink, in: .sites),
        seedEntry(CatalogSeed.gmail, in: .sites),
        seedEntry(CatalogSeed.gitHubLink, in: .sites),
        CatalogEntry(id: "catalog.netflix", name: "Netflix", aliases: ["netflix"], category: .sites,
                     template: "https://www.netflix.com"),
        CatalogEntry(id: "catalog.linkedin", name: "LinkedIn", aliases: ["linkedin"], category: .sites,
                     template: "https://www.linkedin.com"),
        CatalogEntry(id: "catalog.x", name: "X", aliases: ["x", "twitter"], category: .sites,
                     template: "https://x.com"),
        CatalogEntry(id: "catalog.instagram", name: "Instagram", aliases: ["instagram", "ig"], category: .sites,
                     template: "https://www.instagram.com"),
    ]

    /// A Catalog entry that re-installs a default seed: its name, aliases, and
    /// template come straight from the `CatalogSeed` definition (so the listing can
    /// never drift from what the seed pass plants) and it carries the seed's own fixed
    /// id. Re-installing still mints a fresh row at the App edge (ADR 0028) — the id
    /// here is only the Catalog-side identity slug.
    private static func seedEntry(_ seed: CatalogSeed.Seed, in category: CatalogCategory) -> CatalogEntry {
        let def = seed.definition
        return CatalogEntry(
            id: seed.id,
            name: def.name,
            aliases: def.aliases,
            category: category,
            template: def.template
        )
    }

    /// The entries in one category, in shipped order — the page's per-section list.
    public static func entries(in category: CatalogCategory) -> [CatalogEntry] {
        entries.filter { $0.category == category }
    }
}
