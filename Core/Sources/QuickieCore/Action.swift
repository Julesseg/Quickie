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
    /// Open one of the full-screen management pages (CONTEXT.md → Management
    /// page): the typed-to command that surfaces Settings or a library/Fallbacks
    /// list, which otherwise lives only as a filtered result row. Replaces the
    /// old chrome buttons and the combined manage sheet.
    case openPage(ManagementPage)
    /// Create an EventKit reminder from a fully-collected New Reminder capture
    /// (CONTEXT.md → Reminder; issue #37). The core carries only the pure
    /// `ReminderDraft`; the app layer performs it against EventKit — the same
    /// defer-to-the-edge pattern as `copyText` and `openNote`, keeping the capture
    /// loop testable and EventKit-free.
    case createReminder(ReminderDraft)
    case none
}

/// Which full-screen management page an `openPage` outcome opens (CONTEXT.md →
/// Management page). Each is reached as a typed command row, never from chrome,
/// and presents full-screen with its own dismiss affordance.
public enum ManagementPage: Equatable, Hashable, Sendable {
    case settings
    case quicklinks
    case fallbacks
    case notes
    case snippets
}

/// Which kind of Provider an Action came from (CONTEXT.md → Provider): the
/// leading provider badge shown on every Result row (issue #11). Every Action
/// originates from exactly one Provider, so this is the row's identity — distinct
/// from `mainAction`, which is what tapping it *does*.
public enum ActionKind: Equatable, Sendable {
    case quicklink
    /// A Fallback query (ADR 0013): a templated, query-consuming Fallback Action.
    /// Web search is the default-seeded one — no longer a privileged built-in.
    case fallbackQuery
    case snippet
    case note
    case newNote
    case newSnippet
    case calculator
    /// A quick-capture that writes to EventKit — New Reminder (issue #37), and
    /// later New Event. Collects its fields through the breadcrumb and creates the
    /// record without leaving Quickie (CONTEXT.md → Quick capture).
    case reminder
    /// The Settings command row (gearshape) — distinct from the data it has none
    /// of, so it reads as its own thing.
    case settings
    /// A management command row that opens a library/management page it does not
    /// itself belong to — Quicklinks and Fallbacks. A dedicated kind so a command
    /// row never wears the same badge as the data rows it governs (a Quicklinks
    /// command vs a user's Quicklinks, a Fallbacks command vs a Fallback query).
    case managementPage
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
    /// Open a full-screen management page (Settings, Quicklinks, Fallbacks, all
    /// Notes, all Snippets).
    case openPage
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
    /// The ordered, typed Arguments this Action collects through the breadcrumb
    /// before it runs (CONTEXT.md → Argument; issue #37). Empty for a single-step
    /// Action that runs straight from the typed text.
    public let arguments: [Argument]

    private let effect: @Sendable (String?) -> ActionOutcome
    /// How collected Argument values become an outcome (issue #37) — the
    /// final-commit auto-create. Defaults to the single-string `effect` so a
    /// single-step Action needs no multi-step effect; `newReminder` supplies one.
    private let multiStepEffect: @Sendable ([ArgumentValue]) -> ActionOutcome

    public init(
        id: String,
        kind: ActionKind = .quicklink,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        inputTypes: [ContentType] = [],
        outputType: ContentType,
        isFallback: Bool = false,
        arguments: [Argument] = [],
        effect: @escaping @Sendable (String?) -> ActionOutcome,
        multiStepEffect: (@Sendable ([ArgumentValue]) -> ActionOutcome)? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.inputTypes = inputTypes
        self.outputType = outputType
        self.isFallback = isFallback
        self.arguments = arguments
        self.effect = effect
        self.multiStepEffect = multiStepEffect ?? { _ in effect(nil) }
    }

    /// Resolves a multi-step Action's collected Argument values into its outcome
    /// (issue #37) — what the engine returns on the final commit. Single-step
    /// Actions have no Arguments and never reach here.
    public func run(arguments values: [ArgumentValue]) -> ActionOutcome {
        multiStepEffect(values)
    }

    /// Runs the main action. `input` is the raw typed text for Actions that
    /// consume it (Fallback queries and the New Note/New Snippet Fallbacks);
    /// self-contained Actions (static Quicklinks, Snippets, Notes) ignore it.
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
        case .composeNote, .composeSnippet, .createReminder: return .compose
        case .openPage: return .openPage
        case .none: return .none
        }
    }

    /// The closest system Return-key submit label for running this Action from
    /// the highlighted row (CONTEXT.md → Highlighted result): a Fallback query
    /// reads as `.search`, a link as `.go`, and self-contained captures/copies as
    /// `.done`. Platform-agnostic — the app maps it to a SwiftUI `SubmitLabel`.
    /// The outcome *case* is stable regardless of input, so it is read with none.
    public var returnKeyLabel: ReturnKeyLabel {
        // A multi-step Action begins its breadcrumb capture rather than performing
        // an outcome, so its label comes from having Arguments, not from `run()`
        // (whose plain outcome is `.none`): Enter on the highlighted row starts it.
        if !arguments.isEmpty { return .go }
        switch run() {
        case .openURL: return isFallback ? .search : .go
        case .copyText, .composeNote, .composeSnippet, .createReminder: return .done
        case .openNote, .openPage: return .go
        case .none: return .none
        }
    }
}

/// The closest system Return-key submit label for the highlighted result's main
/// action (CONTEXT.md → Highlighted result). A Core enum so the loop can decide
/// the Enter intent without importing SwiftUI; the app maps each case to the
/// matching `SubmitLabel`.
public enum ReturnKeyLabel: Equatable, Sendable {
    case search
    case go
    case done
    case none
}

extension Action {
    /// A Quicklink (CONTEXT.md → Quicklink; ADR 0013): a *static* URL that opens
    /// directly, consuming no typed text and carrying no `{placeholder}`. It
    /// matches by name like any other Action. The query-consuming behaviour has
    /// moved out to `fallbackQuery`, so this type now has exactly one shape — no
    /// auto-detection, no Fallback flag. Quickie ships no default Quicklinks; the
    /// app builds these from the user's stored static links.
    public static func quicklink(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        url: URL
    ) -> Action {
        Action(
            id: id,
            kind: .quicklink,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            inputTypes: [],
            outputType: .url
        ) { _ in .openURL(url) }
    }

    /// Substitutes the typed text into every `{placeholder}` token of a Fallback
    /// query's template (M1's single Argument fills them all), percent-encoding it
    /// for the query string. Only `fallbackQuery` reaches here, and it is built
    /// only from a placeholder-bearing template, so there is always a token to
    /// fill.
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

    /// A Fallback query (CONTEXT.md → Fallback query; ADR 0013): a URL template
    /// that **requires** a `{placeholder}` and consumes the typed text as its
    /// query. Returns `nil` when `template` carries no placeholder — the type's
    /// defining invariant, so a static link can never masquerade as one. It is a
    /// Fallback Action: always surfaced, pinned to the bottom region, fed the raw
    /// typed text. Web search is just a default-seeded instance of this.
    public static func fallbackQuery(
        id: String,
        title: String,
        subtitle: String? = nil,
        aliases: [String] = [],
        template: String
    ) -> Action? {
        guard templateContainsPlaceholder(template) else { return nil }
        return Action(
            id: id,
            kind: .fallbackQuery,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            inputTypes: [.text],
            outputType: .url,
            isFallback: true
        ) { input in
            fill(template: template, with: input)
        }
    }

    /// True when `template` carries at least one real `{placeholder}` token —
    /// the validation both editors use (a Quicklink rejects one, a Fallback query
    /// requires one) and the invariant `fallbackQuery` enforces. An empty `{}`
    /// pair is not a placeholder. Unlike the removed `templateHasPlaceholder`,
    /// this never switches an Action's behaviour — the type does that now.
    public static func templateContainsPlaceholder(_ template: String) -> Bool {
        template.range(of: "\\{[^}]+\\}", options: .regularExpression) != nil
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
    /// that opens the Note library page full-screen. Surfaces the full library as
    /// a filterable, selectable row rather than a chrome button, so browsing notes
    /// lives in the same loop as everything else.
    public static func openNotesLibrary() -> Action {
        Action(
            id: "builtin.notes-library",
            kind: .note,
            title: "All Notes",
            aliases: ["notes", "note library", "browse notes"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.notes) }
    }

    /// The "All Snippets" command (CONTEXT.md → Snippet): the snippet counterpart
    /// to `openNotesLibrary`, opening the Snippet library page full-screen.
    public static func openSnippetsLibrary() -> Action {
        Action(
            id: "builtin.snippets-library",
            kind: .snippet,
            title: "All Snippets",
            aliases: ["snippets", "snippet library", "browse snippets"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.snippets) }
    }

    /// The "Settings" command (CONTEXT.md → Settings, Management page): a typed-to
    /// command row that opens the full-screen Settings page (Appearance) in place
    /// of the old top-right gear button.
    public static func openSettings() -> Action {
        Action(
            id: "builtin.settings",
            kind: .settings,
            title: "Settings",
            aliases: ["preferences", "appearance", "theme"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings) }
    }

    /// The "Quicklinks" command (CONTEXT.md → Quicklink, Management page): opens
    /// the full-screen Quicklinks management page (static links only).
    public static func openQuicklinksPage() -> Action {
        Action(
            id: "builtin.quicklinks-page",
            kind: .managementPage,
            title: "Quicklinks",
            aliases: ["links", "manage quicklinks", "bookmarks"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.quicklinks) }
    }

    /// The "Fallbacks" command (CONTEXT.md → Fallback list, Management page):
    /// opens the unified, reorderable Fallbacks page (Fallback queries + New Note
    /// + New Snippet).
    public static func openFallbacksPage() -> Action {
        Action(
            id: "builtin.fallbacks-page",
            kind: .managementPage,
            title: "Fallbacks",
            aliases: ["fallback", "search engines", "manage fallbacks"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.fallbacks) }
    }
}
