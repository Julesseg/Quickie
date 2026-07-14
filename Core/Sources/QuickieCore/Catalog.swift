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
/// name shown in the "Requires <app>" note for an app-scheme entry. `glyph` is the
/// entry's **default symbol** — the best-matching pick from the curated
/// `CustomActionGlyphCatalog` — shown as the row's leading badge and stamped onto
/// the installed action's `glyph`, so a fresh install already wears a meaningful
/// symbol; it stays the ordinary opt-in field the editor can change or clear.
public struct CatalogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let category: CatalogCategory
    public let template: String
    public let glyph: String?
    public let requiresApp: String?
    public let argumentSpecs: [String: ArgumentSpec]

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        category: CatalogCategory,
        template: String,
        glyph: String? = nil,
        requiresApp: String? = nil,
        argumentSpecs: [String: ArgumentSpec] = [:]
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.template = template
        self.glyph = glyph
        self.requiresApp = requiresApp
        self.argumentSpecs = argumentSpecs
    }

    /// The `CustomActionDefinition` this entry installs — the exact value the create
    /// path persists, so an installed copy is indistinguishable from a hand-made one
    /// (its default glyph included, as if the user had picked it in the editor).
    public var definition: CustomActionDefinition {
        CustomActionDefinition(
            name: name,
            aliases: aliases,
            template: template,
            argumentSpecs: argumentSpecs,
            glyph: glyph
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
    ///
    /// Every entry carries a **default glyph** from the curated
    /// `CustomActionGlyphCatalog` — brand symbols don't exist in SF Symbols, so each
    /// pick is the closest *intent* match (what the action does: search, play, note,
    /// call), validated by `CatalogTests` as a member of the curated set.
    public static let entries: [CatalogEntry] = [
        // Search engines
        CatalogEntry(id: "catalog.google", name: "Google", aliases: ["google"], category: .searchEngines,
                     template: "https://www.google.com/search?q={query}", glyph: "magnifyingglass"),
        CatalogEntry(id: "catalog.duckduckgo", name: "DuckDuckGo", aliases: ["ddg"], category: .searchEngines,
                     template: "https://duckduckgo.com/?q={query}", glyph: "magnifyingglass"),
        CatalogEntry(id: "catalog.bing", name: "Bing", aliases: ["bing"], category: .searchEngines,
                     template: "https://www.bing.com/search?q={query}", glyph: "magnifyingglass"),
        CatalogEntry(id: "catalog.kagi", name: "Kagi", aliases: ["kagi"], category: .searchEngines,
                     template: "https://kagi.com/search?q={query}", glyph: "magnifyingglass"),
        CatalogEntry(id: "catalog.ecosia", name: "Ecosia", aliases: ["ecosia"], category: .searchEngines,
                     template: "https://www.ecosia.org/search?q={query}", glyph: "magnifyingglass"),
        CatalogEntry(id: "catalog.brave", name: "Brave Search", aliases: ["brave"], category: .searchEngines,
                     template: "https://search.brave.com/search?q={query}", glyph: "magnifyingglass"),
        CatalogEntry(id: "catalog.startpage", name: "Startpage", aliases: ["startpage"], category: .searchEngines,
                     template: "https://www.startpage.com/sp/search?query={query}", glyph: "magnifyingglass"),

        // AI chats
        CatalogEntry(id: "catalog.chatgpt", name: "ChatGPT", aliases: ["gpt", "chatgpt"], category: .aiChats,
                     template: "https://chatgpt.com/?q={prompt}", glyph: "sparkles"),
        CatalogEntry(id: "catalog.claude", name: "Claude", aliases: ["claude"], category: .aiChats,
                     template: "https://claude.ai/new?q={prompt}", glyph: "sparkles"),
        CatalogEntry(id: "catalog.perplexity", name: "Perplexity", aliases: ["perplexity"], category: .aiChats,
                     template: "https://www.perplexity.ai/search?q={query}", glyph: "sparkles"),

        // Reference & site search. The three non-web seeds are listed here for
        // re-install (CONTEXT.md → Catalog); their name/aliases/template/glyph are
        // pulled straight from `CatalogSeed` so the two can never drift — the
        // re-install copy is the seed, verbatim, under the seed's own fixed id.
        seedEntry(CatalogSeed.wikipedia, in: .reference),
        seedEntry(CatalogSeed.youTube, in: .reference),
        seedEntry(CatalogSeed.googleMaps, in: .reference),
        seedEntry(CatalogSeed.appStoreSearch, in: .reference),
        CatalogEntry(id: "catalog.amazon", name: "Amazon", aliases: ["amazon"], category: .reference,
                     template: "https://www.amazon.com/s?k={query}", glyph: "cart"),
        CatalogEntry(id: "catalog.reddit", name: "Reddit", aliases: ["reddit"], category: .reference,
                     template: "https://www.reddit.com/search/?q={query}", glyph: "bubble.left.and.bubble.right"),
        CatalogEntry(id: "catalog.github", name: "GitHub", aliases: ["github", "gh"], category: .reference,
                     template: "https://github.com/search?q={query}", glyph: "curlybraces"),
        CatalogEntry(id: "catalog.stackoverflow", name: "Stack Overflow", aliases: ["so", "stackoverflow"], category: .reference,
                     template: "https://stackoverflow.com/search?q={query}", glyph: "curlybraces"),
        CatalogEntry(id: "catalog.imdb", name: "IMDb", aliases: ["imdb"], category: .reference,
                     template: "https://www.imdb.com/find/?q={query}", glyph: "star"),
        CatalogEntry(id: "catalog.wolfram", name: "Wolfram Alpha", aliases: ["wolfram"], category: .reference,
                     template: "https://www.wolframalpha.com/input?i={query}", glyph: "chart.line.uptrend.xyaxis"),
        CatalogEntry(id: "catalog.google-translate", name: "Google Translate", aliases: ["translate"], category: .reference,
                     template: "https://translate.google.com/?sl=auto&tl=en&text={text}", glyph: "globe"),
        CatalogEntry(id: "catalog.deepl", name: "DeepL", aliases: ["deepl"], category: .reference,
                     template: "https://www.deepl.com/translator#auto/en/{text}", glyph: "globe"),
        CatalogEntry(id: "catalog.merriam-webster", name: "Merriam-Webster", aliases: ["dictionary", "define"], category: .reference,
                     template: "https://www.merriam-webster.com/dictionary/{word}", glyph: "book"),

        // App captures
        CatalogEntry(id: "catalog.things", name: "Things", aliases: ["things"], category: .appCaptures,
                     template: "things:///add?title={title}&notes={notes}", glyph: "checklist", requiresApp: "Things"),
        CatalogEntry(id: "catalog.todoist", name: "Todoist", aliases: ["todoist"], category: .appCaptures,
                     template: "todoist://addtask?content={content}", glyph: "checklist", requiresApp: "Todoist"),
        CatalogEntry(id: "catalog.omnifocus", name: "OmniFocus", aliases: ["omnifocus"], category: .appCaptures,
                     template: "omnifocus:///add?name={name}&note={note}", glyph: "checklist", requiresApp: "OmniFocus"),
        CatalogEntry(id: "catalog.bear", name: "Bear", aliases: ["bear"], category: .appCaptures,
                     template: "bear://x-callback-url/create?title={title}&text={text}", glyph: "note.text", requiresApp: "Bear"),
        CatalogEntry(id: "catalog.drafts", name: "Drafts", aliases: ["drafts"], category: .appCaptures,
                     template: "drafts://x-callback-url/create?text={text}", glyph: "pencil", requiresApp: "Drafts"),
        CatalogEntry(id: "catalog.obsidian", name: "Obsidian", aliases: ["obsidian"], category: .appCaptures,
                     template: "obsidian://new?name={name}&content={content}", glyph: "note.text", requiresApp: "Obsidian"),
        CatalogEntry(id: "catalog.dayone", name: "Day One", aliases: ["dayone", "journal"], category: .appCaptures,
                     template: "dayone://post?entry={entry}", glyph: "book", requiresApp: "Day One"),
        CatalogEntry(id: "catalog.fantastical", name: "Fantastical", aliases: ["fantastical"], category: .appCaptures,
                     template: "x-fantastical3://parse?sentence={sentence}", glyph: "calendar", requiresApp: "Fantastical"),
        CatalogEntry(id: "catalog.google-calendar", name: "Google Calendar", aliases: ["gcal", "calendar"], category: .appCaptures,
                     template: "https://calendar.google.com/calendar/render?action=TEMPLATE&text={title}", glyph: "calendar"),

        // Communication & utilities
        CatalogEntry(id: "catalog.email", name: "Email compose", aliases: ["email", "mail"], category: .communication,
                     template: "mailto:{to}?subject={subject}&body={body}", glyph: "envelope"),
        CatalogEntry(id: "catalog.sms", name: "Text a number", aliases: ["sms", "text"], category: .communication,
                     template: "sms:{number}&body={message}", glyph: "message", argumentSpecs: number),
        CatalogEntry(id: "catalog.tel", name: "Call a number", aliases: ["call", "phone"], category: .communication,
                     template: "tel:{number}", glyph: "phone", argumentSpecs: number),
        CatalogEntry(id: "catalog.whatsapp", name: "WhatsApp", aliases: ["whatsapp"], category: .communication,
                     template: "https://wa.me/?text={text}", glyph: "bubble.left.and.bubble.right"),
        CatalogEntry(id: "catalog.telegram", name: "Telegram share", aliases: ["telegram"], category: .communication,
                     template: "https://t.me/share/url?url={url}", glyph: "square.and.arrow.up"),
        CatalogEntry(id: "catalog.spotify", name: "Spotify search", aliases: ["spotify"], category: .communication,
                     template: "https://open.spotify.com/search/{query}", glyph: "music.note"),
        CatalogEntry(id: "catalog.apple-music", name: "Apple Music search", aliases: ["apple music", "music"], category: .communication,
                     template: "https://music.apple.com/search?term={term}", glyph: "music.note"),
        CatalogEntry(id: "catalog.17track", name: "17track package tracking", aliases: ["17track", "track"], category: .communication,
                     template: "https://t.17track.net/en#nums={tracking}", glyph: "mappin.and.ellipse"),
        CatalogEntry(id: "catalog.waze", name: "Waze", aliases: ["waze"], category: .communication,
                     template: "https://waze.com/ul?q={query}", glyph: "car"),

        // Sites — static, slot-less homepage links (ADR 0030). The three default site
        // seeds are listed here for re-install, pulled straight from `CatalogSeed` so
        // they can never drift from what the seed pass plants; the rest are ordinary
        // fresh-id installs. Chosen to avoid name collisions with the *search* entries
        // above (e.g. this is YouTube's homepage, not the YouTube search).
        seedEntry(CatalogSeed.youTubeLink, in: .sites),
        seedEntry(CatalogSeed.gmail, in: .sites),
        seedEntry(CatalogSeed.gitHubLink, in: .sites),
        CatalogEntry(id: "catalog.netflix", name: "Netflix", aliases: ["netflix"], category: .sites,
                     template: "https://www.netflix.com", glyph: "play.rectangle"),
        CatalogEntry(id: "catalog.linkedin", name: "LinkedIn", aliases: ["linkedin"], category: .sites,
                     template: "https://www.linkedin.com", glyph: "building.2"),
        CatalogEntry(id: "catalog.x", name: "X", aliases: ["x", "twitter"], category: .sites,
                     template: "https://x.com", glyph: "bubble.left.and.bubble.right"),
        CatalogEntry(id: "catalog.instagram", name: "Instagram", aliases: ["instagram", "ig"], category: .sites,
                     template: "https://www.instagram.com", glyph: "camera"),
    ]

    /// A Catalog entry that re-installs a default seed: its name, aliases, template,
    /// and default glyph come straight from the `CatalogSeed` definition (so the
    /// listing can never drift from what the seed pass plants) and it carries the
    /// seed's own fixed id. Re-installing still mints a fresh row at the App edge
    /// (ADR 0028) — the id here is only the Catalog-side identity slug.
    private static func seedEntry(_ seed: CatalogSeed.Seed, in category: CatalogCategory) -> CatalogEntry {
        let def = seed.definition
        return CatalogEntry(
            id: seed.id,
            name: def.name,
            aliases: def.aliases,
            category: category,
            template: def.template,
            glyph: def.glyph
        )
    }

    /// The entries in one category, in shipped order — the page's per-section list.
    public static func entries(in category: CatalogCategory) -> [CatalogEntry] {
        entries.filter { $0.category == category }
    }
}
