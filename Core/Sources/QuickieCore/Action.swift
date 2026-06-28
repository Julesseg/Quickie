import Foundation

/// What running an Action's main action *means*, as a value the platform layer
/// performs. The core stays pure — it never opens a URL or touches the
/// pasteboard itself — so the loop (match → rank → run) is fully testable
/// without UIKit. The SwiftUI app interprets the outcome (`openURL` →
/// `UIApplication.open`, `copyText` → `UIPasteboard`).
public enum ActionOutcome: Equatable, Sendable {
    case openURL(URL)
    case copyText(String)
    /// Open a stored Note for reading (CONTEXT.md → Note): a Note's main action.
    /// The core carries only the Note's identity; the app layer resolves it to
    /// the stored body and presents the reader — keeping the loop pure and
    /// testable, exactly like `copyText` defers the pasteboard.
    case openNote(id: String)
    /// Open the Note editor seeded with the raw typed text (CONTEXT.md → Note):
    /// the "New Note" Fallback. The core declares the intent and carries the
    /// seed; the app presents the editor so the user titles and confirms before
    /// it is stored — keeping the flow pure and testable.
    case composeNote(seed: String)
    /// Open the Snippet editor seeded with the raw typed text (CONTEXT.md →
    /// Snippet): the "New Snippet" Fallback, the snippet counterpart to
    /// `composeNote`.
    case composeSnippet(seed: String)
    /// Open one of the library list pages (CONTEXT.md → Snippet / Note): the
    /// main-list command that surfaces the full Snippet or Note library, which
    /// otherwise lives only as filtered result rows.
    case openLibrary(Library)
    case none
}

/// Which library list page an `openLibrary` outcome opens.
public enum Library: Equatable, Sendable {
    case notes
    case snippets
}

/// Which kind of Provider an Action came from (CONTEXT.md → Provider): the
/// leading provider badge shown on every Result row (issue #11). Every Action
/// originates from exactly one Provider, so this is the row's identity — distinct
/// from `mainAction`, which is what tapping it *does*.
public enum ActionKind: Equatable, Sendable {
    case quicklink
    case webSearch
    case snippet
    case note
    case newNote
    case newSnippet
    case calculator
}

/// What tapping a row *does*, as a coarse classification of its `ActionOutcome`
/// — the trailing main-action glyph the Result list shows (issue #11). It is
/// derived from the Action's real outcome, never declared separately, so the
/// glyph can't drift from the behavior.
public enum MainAction: Equatable, Sendable {
    case openInBrowser
    case copyToClipboard
    case openNote
    /// Open an editor to compose a new Note or Snippet from the typed text.
    case compose
    /// Open a library list page (all Notes / all Snippets).
    case openLibrary
    case none
}

/// A single invokable capability shown in the Result list — the one kind of
/// thing in the index. Every subsystem (matcher, ranking, providers) operates
/// on Actions. An Action declares its typed input/output content (ADR 0011)
/// and carries a *main action*: the effect tapping its row performs, exposed
/// as `run(input:)`.
public struct Action: Identifiable, Sendable {
    public let id: String
    /// Which Provider this Action came from — drives the leading provider badge.
    public let kind: ActionKind
    /// The name shown in the row and matched against the query.
    public let title: String
    public let subtitle: String?
    /// Alternative names also matched against the query.
    public let aliases: [String]
    /// Content type(s) this Action consumes (empty for a self-contained link).
    public let inputTypes: [ContentType]
    /// The content type this Action produces.
    public let outputType: ContentType
    /// Whether this Action is a Fallback: always surfaced in the Result list,
    /// pinned in the bottom fallback region, consuming the raw typed text rather
    /// than matching by name (CONTEXT.md → Fallback Action).
    public let isFallback: Bool

    private let effect: @Sendable (String?) -> ActionOutcome

    public init(
        id: String,
        kind: ActionKind = .quicklink,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        inputTypes: [ContentType] = [],
        outputType: ContentType,
        isFallback: Bool = false,
        effect: @escaping @Sendable (String?) -> ActionOutcome
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.inputTypes = inputTypes
        self.outputType = outputType
        self.isFallback = isFallback
        self.effect = effect
    }

    /// Runs the main action. `input` is the raw typed text for Actions that
    /// consume it (Fallbacks/placeholder-Quicklinks); self-contained Actions
    /// ignore it.
    public func run(input: String? = nil) -> ActionOutcome {
        effect(input)
    }

    /// The trailing main-action glyph's meaning, classified from the Action's own
    /// outcome (issue #11). The outcome *case* is stable regardless of the typed
    /// input for every current Action, so this is read with no input and the
    /// glyph always matches what a tap performs.
    public var mainAction: MainAction {
        switch run() {
        case .openURL: return .openInBrowser
        case .copyText: return .copyToClipboard
        case .openNote: return .openNote
        case .composeNote, .composeSnippet: return .compose
        case .openLibrary: return .openLibrary
        case .none: return .none
        }
    }
}

extension Action {
    /// A Quicklink built from a single stored URL *template* (CONTEXT.md →
    /// Quicklink). The one field drives both shapes: a template with a
    /// `{placeholder}` token takes the typed text as its Argument and
    /// substitutes it (consuming `.text`); a template with none opens directly
    /// (consuming nothing). This is the auto-detecting model the SwiftData store
    /// persists and the manage UI edits — no static/placeholder mode toggle.
    public static func quicklink(
        id: String,
        kind: ActionKind = .quicklink,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        template: String,
        isFallback: Bool = false
    ) -> Action {
        let hasPlaceholder = templateHasPlaceholder(template)
        return Action(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            inputTypes: hasPlaceholder ? [.text] : [],
            outputType: .url,
            isFallback: isFallback
        ) { input in
            fill(template: template, with: input)
        }
    }

    /// True when `template` carries at least one `{placeholder}` token — the
    /// signal that the Quicklink takes an Argument rather than opening directly.
    /// Exposed so the app's editor can mirror the same static-vs-placeholder
    /// detection the factory uses (issue #5).
    public static func templateHasPlaceholder(_ template: String) -> Bool {
        template.range(of: "\\{[^}]+\\}", options: .regularExpression) != nil
    }

    /// Substitutes the typed text into every `{placeholder}` token (M1's single
    /// Argument fills them all), percent-encoding it for the query string. A
    /// template with no placeholder ignores `input` and opens as stored.
    ///
    /// The substitution is *literal*: each `{…}` token is matched, then replaced
    /// with the encoded text as a plain string. We never feed the typed text to
    /// a regex replacement template, where `$1`/`\` would be read as capture
    /// references — `.urlQueryAllowed` leaves `$` unescaped, so "$5 menu" would
    /// otherwise lose its "$5".
    private static func fill(template: String, with input: String?) -> ActionOutcome {
        let raw = input ?? ""
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw

        // Replace one token at a time, re-scanning from the start. This
        // terminates because the encoded text can never contain `{`/`}` (both
        // are escaped by `.urlQueryAllowed`), so each pass strictly removes one
        // token and never introduces a new one.
        var filled = template
        while let token = filled.range(of: "\\{[^}]+\\}", options: .regularExpression) {
            filled.replaceSubrange(token, with: encoded)
        }

        guard let url = URL(string: filled) else { return .none }
        return .openURL(url)
    }

    /// A static Quicklink: a fixed URL that opens directly, consuming no input
    /// (CONTEXT.md → Quicklink with no placeholder). A convenience over
    /// `quicklink` for callers that already hold a parsed `URL` (the built-in
    /// Indexed Provider). A placeholder-free URL routes through the same
    /// substitution path, so it simply opens as stored.
    public static func staticLink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        url: URL
    ) -> Action {
        quicklink(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            template: url.absoluteString
        )
    }

    /// The built-in web-search Fallback (CONTEXT.md → Fallback Action): a
    /// placeholder-Quicklink, flagged a Fallback, that consumes the raw typed
    /// text. The search engine *is* the template, so swapping engines is just
    /// passing a different one — "the default search engine is editable." The
    /// app persists the chosen template and passes it here.
    public static func webSearch(
        template: String = "https://duckduckgo.com/?q={query}"
    ) -> Action {
        quicklink(
            id: "builtin.web-search",
            kind: .webSearch,
            title: "Search the web",
            aliases: ["search", "google", "ddg"],
            template: template,
            isFallback: true
        )
    }

    /// A placeholder-Quicklink: a URL template with a `{placeholder}` token the
    /// typed text fills (CONTEXT.md → Quicklink, Fallback Action). A thin alias
    /// over `quicklink` for call sites that read better naming the placeholder
    /// intent explicitly; both share one substitution path.
    public static func placeholderLink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        template: String,
        isFallback: Bool = false
    ) -> Action {
        quicklink(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            template: template,
            isFallback: isFallback
        )
    }

    /// A Snippet: saved, reusable text whose main action is **Copy**
    /// (CONTEXT.md → Snippet). Self-contained — it ignores the typed text and
    /// always copies its stored `body` to the clipboard, which is what
    /// distinguishes it from a Note (copy-out vs read).
    public static func snippet(
        id: String,
        title: String,
        body: String
    ) -> Action {
        Action(
            id: id,
            kind: .snippet,
            title: title,
            inputTypes: [],
            outputType: .text
        ) { _ in .copyText(body) }
    }

    /// A Note: a captured free-text thought whose main action is **Open/read**
    /// (CONTEXT.md → Note). Self-contained — it ignores the typed text and
    /// resolves to `openNote(id:)`, which the app turns into the reader. This is
    /// the read-vs-copy-out distinction from a Snippet: same storage, opposite
    /// main action. The Note's body lives in the store; the Action carries only
    /// its identity and title so it matches and ranks like any other capability.
    public static func note(
        id: String,
        title: String
    ) -> Action {
        Action(
            id: id,
            kind: .note,
            title: title,
            inputTypes: [],
            outputType: .text
        ) { _ in .openNote(id: id) }
    }

    /// The "New Note" Fallback (CONTEXT.md → Note, Fallback Action): a
    /// Fallback-style action that always rides in the bottom region and, when
    /// run, opens the Note editor seeded with the user's literal typed text. Like
    /// the web-search Fallback it consumes the raw text; the outcome is
    /// `composeNote`, which the app turns into a seeded editor the user titles and
    /// confirms before it is stored.
    public static func newNote() -> Action {
        Action(
            id: "builtin.new-note",
            kind: .newNote,
            title: "New Note",
            aliases: ["note", "capture", "jot"],
            inputTypes: [.text],
            outputType: .text,
            isFallback: true
        ) { input in .composeNote(seed: input ?? "") }
    }

    /// The "New Snippet" Fallback (CONTEXT.md → Snippet, Fallback Action): the
    /// snippet counterpart to `newNote`. It rides the bottom region and, when run,
    /// opens the Snippet editor seeded with the typed text as the copy-out body,
    /// which the user titles and confirms before it is stored.
    public static func newSnippet() -> Action {
        Action(
            id: "builtin.new-snippet",
            kind: .newSnippet,
            title: "New Snippet",
            aliases: ["snippet", "clip", "save text"],
            inputTypes: [.text],
            outputType: .text,
            isFallback: true
        ) { input in .composeSnippet(seed: input ?? "") }
    }

    /// The "All Notes" command (CONTEXT.md → Note): a built-in main-list Action
    /// that opens the Note library list page. Surfaces the full library as a
    /// filterable, selectable row rather than a chrome button, so browsing notes
    /// lives in the same loop as everything else.
    public static func openNotesLibrary() -> Action {
        Action(
            id: "builtin.notes-library",
            kind: .note,
            title: "All Notes",
            aliases: ["notes", "note library", "browse notes"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openLibrary(.notes) }
    }

    /// The "All Snippets" command (CONTEXT.md → Snippet): the snippet counterpart
    /// to `openNotesLibrary`, opening the Snippet library list page.
    public static func openSnippetsLibrary() -> Action {
        Action(
            id: "builtin.snippets-library",
            kind: .snippet,
            title: "All Snippets",
            aliases: ["snippets", "snippet library", "browse snippets"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openLibrary(.snippets) }
    }
}
