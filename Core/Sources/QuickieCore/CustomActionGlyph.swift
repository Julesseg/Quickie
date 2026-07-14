import Foundation

/// One entry in the **curated glyph catalog** the Custom Action editor offers
/// (CONTEXT.md → Custom Action; issue #163): an SF Symbol a user may pick as their
/// action's leading glyph. Carries the symbol `name` (the value stored on the
/// definition and rendered by the App's badge), a human `label` shown in the
/// picker, and extra `keywords` folded into the fuzzy search so a symbol is found
/// by intent ("mail" → `envelope`) as well as by its literal name.
///
/// The catalog is Core data — pure strings — so the picker's fuzzy search reuses
/// the same `Matcher` the choice input method uses and stays `swift test`-covered;
/// the App only turns a chosen `name` into an `Image(systemName:)` at its render
/// edge, the same split as the kind-derived badge lookup.
public struct GlyphOption: Identifiable, Equatable, Sendable {
    /// The SF Symbol name — the value stored on the Custom Action and the picker
    /// row's identity, so a symbol appears at most once.
    public let name: String
    /// The human-readable label shown beside the symbol in the picker.
    public let label: String
    /// Extra search terms folded into the fuzzy match, so a symbol is reachable by
    /// intent as well as by its label ("todo" → `checklist`).
    public let keywords: [String]

    public init(name: String, label: String, keywords: [String] = []) {
        self.name = name
        self.label = label
        self.keywords = keywords
    }

    public var id: String { name }

    /// The strings the fuzzy search scores against — the label and every keyword,
    /// deduped implicitly by taking the best per-candidate score. The symbol name
    /// itself rides along so a user who knows the exact SF Symbol name still finds it.
    var searchTerms: [String] { [label, name] + keywords }
}

/// The **curated SF Symbol set** the Custom Action editor's glyph picker offers
/// (CONTEXT.md → Custom Action; issue #163): a hand-picked, intentionally small
/// gallery — not the tens of thousands of SF Symbols — grouped loosely by the
/// things a launcher's Custom Actions tend to be (search, links, communication,
/// media, productivity, files, travel, money, system). Searchable via the same
/// fuzzy-find furniture the choice input method uses (`Matcher`), so the picker
/// ranks best-match-first exactly like a breadcrumb choice step.
public enum CustomActionGlyphCatalog {
    /// The curated options, in a stable display order (the order an empty search
    /// shows). Kept modest so the picker reads as a considered set rather than a
    /// symbol dump; each carries intent keywords so search finds it by meaning.
    public static let all: [GlyphOption] = [
        // Search & web
        GlyphOption(name: "magnifyingglass", label: "Search", keywords: ["find", "look", "query", "web"]),
        GlyphOption(name: "globe", label: "Globe", keywords: ["web", "internet", "site", "world", "browser"]),
        GlyphOption(name: "link", label: "Link", keywords: ["url", "chain", "website", "bookmark"]),
        GlyphOption(name: "safari", label: "Browser", keywords: ["safari", "web", "compass"]),
        GlyphOption(name: "network", label: "Network", keywords: ["web", "connection", "internet"]),

        // Communication
        GlyphOption(name: "envelope", label: "Mail", keywords: ["email", "message", "send", "letter"]),
        GlyphOption(name: "message", label: "Message", keywords: ["chat", "text", "sms", "bubble"]),
        GlyphOption(name: "bubble.left.and.bubble.right", label: "Chat", keywords: ["conversation", "talk", "messages"]),
        GlyphOption(name: "phone", label: "Phone", keywords: ["call", "dial", "telephone"]),
        GlyphOption(name: "video", label: "Video call", keywords: ["camera", "facetime", "meet", "call"]),
        GlyphOption(name: "person.crop.circle", label: "Contact", keywords: ["person", "profile", "account", "user"]),

        // Media
        GlyphOption(name: "play.rectangle", label: "Play video", keywords: ["youtube", "watch", "media", "stream"]),
        GlyphOption(name: "music.note", label: "Music", keywords: ["song", "audio", "spotify", "play"]),
        GlyphOption(name: "photo", label: "Photo", keywords: ["image", "picture", "gallery"]),
        GlyphOption(name: "camera", label: "Camera", keywords: ["photo", "capture", "snapshot"]),
        GlyphOption(name: "headphones", label: "Headphones", keywords: ["audio", "podcast", "listen"]),
        GlyphOption(name: "gamecontroller", label: "Game", keywords: ["play", "gaming", "controller"]),

        // Productivity
        GlyphOption(name: "checklist", label: "Checklist", keywords: ["todo", "tasks", "reminders", "list"]),
        GlyphOption(name: "list.bullet", label: "List", keywords: ["items", "bullets", "notes"]),
        GlyphOption(name: "note.text", label: "Note", keywords: ["notes", "text", "write", "memo"]),
        GlyphOption(name: "calendar", label: "Calendar", keywords: ["date", "event", "schedule", "day"]),
        GlyphOption(name: "clock", label: "Clock", keywords: ["time", "timer", "alarm", "hour"]),
        GlyphOption(name: "bookmark", label: "Bookmark", keywords: ["save", "favorite", "read later"]),
        GlyphOption(name: "book", label: "Book", keywords: ["read", "wikipedia", "reference", "library"]),
        GlyphOption(name: "pencil", label: "Edit", keywords: ["write", "compose", "pen"]),
        GlyphOption(name: "tag", label: "Tag", keywords: ["label", "category", "price"]),

        // Files
        GlyphOption(name: "doc", label: "Document", keywords: ["file", "paper", "page"]),
        GlyphOption(name: "folder", label: "Folder", keywords: ["directory", "files", "storage"]),
        GlyphOption(name: "tray", label: "Tray", keywords: ["inbox", "collect", "queue"]),
        GlyphOption(name: "square.and.arrow.up", label: "Share", keywords: ["export", "send", "upload"]),
        GlyphOption(name: "arrow.down.circle", label: "Download", keywords: ["save", "get", "import"]),

        // Places & travel
        GlyphOption(name: "map", label: "Map", keywords: ["location", "directions", "navigate"]),
        GlyphOption(name: "mappin.and.ellipse", label: "Location", keywords: ["place", "pin", "map", "here"]),
        GlyphOption(name: "car", label: "Car", keywords: ["drive", "vehicle", "travel", "ride"]),
        GlyphOption(name: "airplane", label: "Flight", keywords: ["plane", "travel", "trip", "fly"]),
        GlyphOption(name: "house", label: "Home", keywords: ["house", "main", "start"]),
        GlyphOption(name: "building.2", label: "Building", keywords: ["office", "work", "company"]),

        // Money & commerce
        GlyphOption(name: "cart", label: "Cart", keywords: ["shop", "buy", "store", "purchase"]),
        GlyphOption(name: "bag", label: "Shopping", keywords: ["shop", "buy", "store"]),
        GlyphOption(name: "creditcard", label: "Payment", keywords: ["card", "money", "pay", "bank"]),
        GlyphOption(name: "dollarsign.circle", label: "Money", keywords: ["dollar", "cash", "price", "currency"]),
        GlyphOption(name: "chart.line.uptrend.xyaxis", label: "Chart", keywords: ["stats", "graph", "trend", "analytics"]),

        // Tools & system
        GlyphOption(name: "gearshape", label: "Settings", keywords: ["preferences", "gear", "config", "options"]),
        GlyphOption(name: "wrench.and.screwdriver", label: "Tools", keywords: ["utility", "fix", "build"]),
        GlyphOption(name: "terminal", label: "Terminal", keywords: ["code", "command", "shell", "console"]),
        GlyphOption(name: "curlybraces", label: "Code", keywords: ["braces", "developer", "json", "programming"]),
        GlyphOption(name: "bolt", label: "Bolt", keywords: ["fast", "power", "energy", "quick", "action"]),
        GlyphOption(name: "sparkles", label: "Sparkles", keywords: ["ai", "magic", "new", "shine"]),
        GlyphOption(name: "star", label: "Star", keywords: ["favorite", "rate", "important"]),
        GlyphOption(name: "heart", label: "Heart", keywords: ["like", "love", "favorite"]),
        GlyphOption(name: "flag", label: "Flag", keywords: ["mark", "report", "milestone"]),
        GlyphOption(name: "bell", label: "Bell", keywords: ["notification", "alert", "remind"]),
        GlyphOption(name: "lock", label: "Lock", keywords: ["secure", "private", "password"]),
        GlyphOption(name: "key", label: "Key", keywords: ["password", "access", "unlock", "login"]),
    ]

    /// The curated options filtered by `query` and ranked best-first by the same
    /// `Matcher` the choice input method uses (CONTEXT.md → Input method; issue #163)
    /// — so the editor renders them in a reversed list with the best match nearest
    /// the thumb, exactly like a breadcrumb choice step. An empty query shows every
    /// option in its supplied display order; a query scores each option by the best
    /// of its label, symbol name, and keywords (an option matched by a keyword ranks
    /// by how well that keyword matched), dropping options nothing matched.
    public static func search(_ query: String, layout: KeyboardLayout = .qwerty) -> [GlyphOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }

        return all
            .compactMap { option -> (option: GlyphOption, score: Double)? in
                let best = option.searchTerms
                    .compactMap { Matcher.score(query: trimmed, candidate: $0, layout: layout) }
                    .max()
                guard let best else { return nil }
                return (option, best)
            }
            // Ties break by label so the order is stable and testable, matching the
            // choice step's `label`-ascending tie-break.
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.option.label < $1.option.label }
            .map(\.option)
    }
}
