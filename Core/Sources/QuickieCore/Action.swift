import Foundation

/// What running an Action's main action *means*, as a value the platform layer
/// performs. The core stays pure — it never opens a URL or touches the
/// pasteboard itself — so the loop (match → rank → run) is fully testable
/// without UIKit. The SwiftUI app interprets the outcome (`openURL` →
/// `UIApplication.open`, `copyText` → `UIPasteboard`).
public enum ActionOutcome: Equatable, Sendable {
    case openURL(URL)
    case copyText(String)
    /// Copy the text **and** stage it back into the input (CONTEXT.md → main
    /// action; a math result's main action). It fuses `copyText`'s clipboard
    /// write with the same query-reinjection as `stagePileEntry` — the answer
    /// lands on the pasteboard *and* replaces the query so the matcher re-runs,
    /// leaving the user "typing" the result to keep calculating (`4` → `4 * 3`).
    /// Unlike `stagePileEntry` it carries the literal text, not a store id: there
    /// is nothing to resolve and nothing to consume, so it reads as a Copy row
    /// (the copy is the headline; the staging is the "also").
    case copyAndStage(text: String)
    /// Save the raw typed text into the Pile, silently (CONTEXT.md → Pile; ADR
    /// 0018): the "Save for later" Fallback. No editor, no confirm step, no app
    /// switch — the core declares the capture and carries the text; the app
    /// stores it at the edge, the same defer-to-the-edge pattern as `copyText`.
    case saveToPile(text: String)
    /// Stage a Pile entry (CONTEXT.md → Pile, Stage; ADR 0018): a Pile entry's
    /// main action. The core carries only the entry's identity; the app resolves
    /// it to the stored text, replaces the input query with it (the matcher
    /// re-runs — the same reinjection move as a Shortcut Action's returned
    /// output), and removes the entry from the Pile: staging consumes it.
    case stagePileEntry(id: String)
    /// Open the Snippet editor seeded with the raw typed text (CONTEXT.md →
    /// Snippet): the "New Snippet" Fallback — the user titles and confirms
    /// before it is stored, unlike the Pile's silent capture.
    case composeSnippet(seed: String)
    /// Open one of the full-screen management pages (CONTEXT.md → Management
    /// page): the typed-to command that surfaces Settings or a library/Fallbacks
    /// list, which otherwise lives only as a filtered result row. Replaces the
    /// old chrome buttons and the combined manage sheet.
    case openPage(ManagementPage)
    /// Create an EventKit reminder from a fully-collected New Reminder capture
    /// (CONTEXT.md → Reminder; issue #37). The core carries only the pure
    /// `ReminderDraft`; the app layer performs it against EventKit — the same
    /// defer-to-the-edge pattern as `copyText`, keeping the capture loop
    /// testable and EventKit-free.
    case createReminder(ReminderDraft)
    /// Create an EventKit calendar event from a fully-collected New Event capture
    /// in **silent** mode (CONTEXT.md → Event; issue #38). The core carries only the
    /// pure `EventDraft`; the app writes it to EventKit directly — the silent-default
    /// counterpart to `createReminder`.
    case createEvent(EventDraft)
    /// Hand a fully-collected New Event capture to the system event editor in
    /// **editor** mode (CONTEXT.md → Event; issue #38): the app pre-fills an
    /// `EKEventEditViewController` from the `EventDraft` for final review and native
    /// fields (alerts, invitees, recurrence) instead of writing silently — the
    /// event counterpart to `composeSnippet`'s "open editor, confirm".
    case composeEvent(EventDraft)
    /// Open a file surfaced by File Search (CONTEXT.md → File Search; ADR 0015).
    /// The core carries only the file's Indexed-Folder bookmark identity plus its
    /// relative path within that folder — never a filesystem URL. The app resolves
    /// the pair to a security-scoped URL under a start/stop bracket and opens it
    /// (QuickLook / share), the same defer-to-the-edge pattern as `copyText`.
    case openFile(bookmarkID: String, relativePath: String)
    /// Enter the **Search Files context** (CONTEXT.md → Search Files context; ADR
    /// 0014): the scoped, uncapped file-browsing surface the "Search Files" command
    /// row opens. Entered by selecting a row — never a mode toggle — so it is an
    /// outcome the app performs (scope the input to the file index, show the
    /// breadcrumb) rather than a chrome flip. It commits no value: it is a live
    /// scoped filter, not an Argument slot.
    case enterFileSearch
    /// Run one of the user's iOS Shortcuts by name via x-callback-url (CONTEXT.md →
    /// Shortcut Action; issue #46). The core carries only the shortcut's `name` and
    /// the optional `input` collected through the breadcrumb — never a URL. The app
    /// builds the `shortcuts://x-callback-url/run-shortcut` open (with the
    /// `quickie://` success/error/cancel callbacks) at the platform edge, the same
    /// defer-to-the-edge pattern as `openURL`. The returned output does *not* ride
    /// here: it comes back through the inbound `quickie://shortcut-result` route and
    /// is reinjected as the new query (`ShortcutRun`).
    case runShortcut(name: String, input: String?)
    case none
}

/// Which full-screen management page an `openPage` outcome opens (CONTEXT.md →
/// Management page). Each is reached as a typed command row, never from chrome,
/// and presents full-screen with its own dismiss affordance.
public enum ManagementPage: Equatable, Hashable, Sendable {
    /// The Settings hub (ADR 0019; issue #66). `panel: nil` is the top-level
    /// page (app-level section + the Providers list); a `ProviderID` panel
    /// deeplinks straight to that provider's unified Management page — the
    /// target every Settings command row routes to.
    case settings(panel: ProviderID?)
    /// The Pile **entries** page (CONTEXT.md → Pile; ADR 0018): pure content to
    /// view and act on — tap stages, swipe discards. The entries are temporary,
    /// so their page is deliberately NOT the Pile provider's settings page
    /// (`.settings(panel: .pile)`, reached from the hub's Providers list): the
    /// one carve-out from ADR 0019's unified page, because a transient to-do
    /// list is content, not configuration.
    case pile
}

/// Which kind of Provider an Action came from (CONTEXT.md → Provider): the
/// leading provider badge shown on every Result row (issue #11). Every Action
/// originates from exactly one Provider, so this is the row's identity — distinct
/// from `mainAction`, which is what tapping it *does*.
///
/// `String`-backed and `Codable` so the Favorites widget snapshot (ADR 0025) can
/// carry a Favorite's kind across the App Group as a stable name; the raw values
/// are a persisted format, so renaming a case must keep its raw value.
public enum ActionKind: String, Equatable, Sendable, Codable {
    /// A **static (slot-less) Custom Action** (CONTEXT.md → Custom Action; ADR 0030):
    /// a Custom Action whose URL carries no `{slot}`, so it opens directly (the former
    /// Quicklink). A distinct kind only so its Result row wears the **link** leading
    /// glyph rather than the slotted action's curly-braces — both attribute to the
    /// one Custom Actions provider. The raw value stays `quicklink` (a persisted format
    /// the Favorites widget carries; renaming would re-key stored snapshots).
    case quicklink
    /// A slotted **Custom Action** (CONTEXT.md → Custom Action; ADR 0021): a user-
    /// authored URL template whose `{name}` slots become the breadcrumb's Arguments. It
    /// absorbs the retired Fallback query wholesale — web search is the default-seeded,
    /// fallback-flagged one-Argument instance, no longer a privileged built-in.
    case customAction
    case snippet
    /// A Pile entry (CONTEXT.md → Pile; ADR 0018): a raw query text saved to
    /// deal with later, whose main action stages it back into the input. Its own
    /// kind so the row wears the Pile's tray badge.
    case pile
    /// An imported Shortcut Action (CONTEXT.md → Shortcut Action; issue #45): runs
    /// one of the user's iOS Shortcuts by name. Registered solely by the Sync
    /// Shortcut import (ADR 0007); its own kind so the row wears a Shortcuts badge.
    case shortcut
    /// The "Save for later" Fallback (CONTEXT.md → Pile; ADR 0018): the silent
    /// capture that drops the typed text into the Pile. Its own kind so the row
    /// wears the save-to-tray badge, distinct from the Pile entries it creates.
    case saveForLater
    case newSnippet
    case calculator
    /// A quick-capture that writes a reminder to EventKit — New Reminder (issue
    /// #37). Collects its fields through the breadcrumb and creates the record
    /// without leaving Quickie (CONTEXT.md → Quick capture).
    case reminder
    /// A quick-capture that writes a calendar event to EventKit — New Event (issue
    /// #38). Its own kind so the row wears a calendar badge, not the reminder's
    /// checklist, and the launcher routes its activation to the event capture.
    case event
    /// The Settings command row (gearshape) — distinct from the data it has none
    /// of, so it reads as its own thing.
    case settings
    /// A file surfaced by File Search (CONTEXT.md → File Search; ADR 0015): its own
    /// kind so a file row wears a document badge, distinct from the Indexed Folders
    /// management command that governs where files come from.
    case file
    /// The "Search Files" command row (CONTEXT.md → Search Files context; ADR 0014):
    /// its own kind so it reads as the entry point to the scoped file-browsing
    /// surface, distinct from a `file` result row and from the Indexed Folders
    /// management command.
    case searchFiles
    /// A management command row that opens a library/management page it does not
    /// itself belong to — the Fallbacks page. A dedicated kind so a command row never
    /// wears the same badge as the data rows it governs (a Fallbacks command vs a
    /// Custom Action).
    case managementPage
    /// A System provider built-in (CONTEXT.md → System provider; ADR 0029): the
    /// permanent OS-integration action Open iOS Settings. Its own kind so the row
    /// wears the System badge, and it is disable-only (no delete), governed by the
    /// System umbrella. (App Store Search is a default-seeded Custom Action, not a
    /// System built-in — it opens a slotted URL, so it fits the Custom Action model.)
    case system
}

/// What tapping a row *does*, as a coarse classification of its `ActionOutcome`
/// — the trailing main-action glyph the Result list shows (issue #11). It is
/// derived from the Action's real outcome, never declared separately, so the
/// glyph can't drift from the behavior.
public enum MainAction: Equatable, Sendable {
    case openInBrowser
    case copyToClipboard
    /// Stage a Pile entry's text back into the input (CONTEXT.md → Stage): the
    /// query is replaced, the matcher re-runs, and the entry leaves the Pile.
    case stage
    /// Silently drop the typed text into the Pile (CONTEXT.md → Pile): the
    /// "Save for later" capture — no editor, so it is not a compose.
    case saveToPile
    /// Open an editor to compose a new Snippet from the typed text.
    case compose
    /// Open a full-screen management page (Settings, Custom Actions, Fallbacks, the
    /// Pile, all Snippets).
    case openPage
    /// Open a file surfaced by File Search — the app resolves its bookmark identity
    /// to a security-scoped URL and opens it (CONTEXT.md → File Search).
    case openFile
    /// Enter the Search Files context — the "Search Files" command's tap scopes the
    /// input to the file index (CONTEXT.md → Search Files context; ADR 0014).
    case searchFiles
    /// Run one of the user's iOS Shortcuts by name (CONTEXT.md → Shortcut Action;
    /// issue #46): the app hands off to the Shortcuts app via x-callback-url.
    case runShortcut
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
    /// The ordered, typed Arguments this Action collects through the breadcrumb
    /// before it runs (CONTEXT.md → Argument; issue #37). Empty for a single-step
    /// Action that runs straight from the typed text.
    public let arguments: [Argument]
    /// The concrete value/reference this row carries (CONTEXT.md → Result content;
    /// ADR 0017): a **declared** property, distinct from `mainAction`, that the
    /// long-press menu keys its secondary actions off. Encodes presence *and*
    /// value, so a text-bearing Snippet (`.text`) is told apart from a text-*typed*
    /// command (`.none`). Declared per factory rather than derived from the
    /// outcome, because the outcome alone is ambiguous — a Calculator copies text
    /// yet reads as `.number`, and an inert Shortcut has a `.none` outcome.
    public let content: ResultContent

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
        arguments: [Argument] = [],
        content: ResultContent? = nil,
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
        self.arguments = arguments
        // Content is a declared property (ADR 0017). Factories that carry a value
        // pass it explicitly; when omitted it defaults to a derive-from-outcome
        // helper so a content-bearing Action never silently reads as `.none` —
        // the one factory the derivation can't get right (Calculator → `.number`)
        // overrides it.
        self.content = content ?? Action.derivedContent(from: effect(nil))
        self.effect = effect
        self.multiStepEffect = multiStepEffect ?? { _ in effect(nil) }
    }

    /// The default `ResultContent` for an outcome, used when a factory does not
    /// declare one (ADR 0017). Terminal outcomes with no carried value read as
    /// `.none`, so a command / capture / shortcut row exposes no secondary
    /// actions. This is a *default*, not the source of truth: `content` is a
    /// declared, stored property a factory can override (e.g. Calculator).
    private static func derivedContent(from outcome: ActionOutcome) -> ResultContent {
        switch outcome {
        case .openURL:
            return .url
        case .copyText, .copyAndStage:
            return .text
        case .stagePileEntry(let id):
            return .pileEntry(id: id)
        case .openFile(let bookmarkID, let relativePath):
            return .file(bookmarkID: bookmarkID, relativePath: relativePath)
        case .saveToPile, .composeSnippet, .openPage, .createReminder,
             .createEvent, .composeEvent, .enterFileSearch, .runShortcut, .none:
            return .none
        }
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
    ///
    /// A multi-step capture (New Reminder) produces its outcome only from the
    /// Arguments it collects, so its plain `run()` is the placeholder `.none`; it
    /// is classified from the multi-step outcome instead (the case is stable
    /// regardless of the values, the same way the single-step case is stable
    /// regardless of input), so the row wears the glyph of what it ultimately does.
    public var mainAction: MainAction {
        let outcome = arguments.isEmpty ? run() : run(arguments: [])
        switch outcome {
        case .openURL: return .openInBrowser
        // `copyAndStage` reads as Copy: the copy is the headline outcome (glyph
        // and Enter hint), and the staging that keeps the user calculating is the
        // "also" — visible when the input becomes the answer, not a second glyph.
        case .copyText, .copyAndStage: return .copyToClipboard
        case .stagePileEntry: return .stage
        case .saveToPile: return .saveToPile
        case .composeSnippet, .createReminder, .createEvent, .composeEvent: return .compose
        case .openPage: return .openPage
        case .openFile: return .openFile
        case .enterFileSearch: return .searchFiles
        case .runShortcut: return .runShortcut
        case .none: return .none
        }
    }

    /// The closest system Return-key submit label for running this Action from
    /// the highlighted row (CONTEXT.md → Highlighted result): a fallback that opens
    /// a URL (a web search) reads as `.search`, a link as `.go`, and self-contained captures/copies as
    /// `.done`. Platform-agnostic — the app maps it to a SwiftUI `SubmitLabel`.
    /// The outcome *case* is stable regardless of input, so it is read with none.
    public var returnKeyLabel: ReturnKeyLabel {
        // A multi-step Action begins its breadcrumb capture rather than performing
        // an outcome, so its label comes from having Arguments, not from `run()`
        // (whose plain outcome is `.none`): Enter on the highlighted row starts it.
        // A fallback-eligible one whose commit opens a URL — a text-first Custom Action
        // used as a search, web search the seed — still reads `.search`, matching the
        // way a one-tap web query has always read; every other multi-step row reads `.go`.
        if !arguments.isEmpty {
            if isFallbackEligible, case .openURL = run(arguments: []) { return .search }
            return .go
        }
        switch run() {
        case .openURL: return isFallbackEligible ? .search : .go
        case .copyText, .copyAndStage, .saveToPile, .composeSnippet, .createReminder, .createEvent, .composeEvent: return .done
        case .stagePileEntry, .openPage, .openFile, .enterFileSearch, .runShortcut: return .go
        case .none: return .none
        }
    }

    /// Whether this Action can ride the bottom fallback region — **derived from
    /// shape, never declared** (CONTEXT.md → Fallback Action; the retired fallback
    /// flag). An Action is eligible when its first Argument is free text, so the
    /// seeded query has somewhere to land: every text-first Custom Action and every
    /// Shortcut with "accepts input" on qualifies automatically. The two built-in
    /// captures (Save for later, New Snippet) consume the raw typed text through
    /// their single-step `effect` rather than a declared Argument, so they are
    /// eligible by kind. The New Reminder and New Event captures lead with a free-text
    /// **Title** step (issue #145 follow-up), so a fallback selection seeds that title
    /// and the breadcrumb continues from the next step — they are eligible by kind too.
    /// Quicklinks, Snippets, files, and commands have nowhere to put the query and are
    /// never eligible.
    ///
    /// Eligibility only *admits* an Action to the Fallback list's disabled pool; the
    /// user activates it there. Membership in the user's enabled list — not this
    /// predicate — decides what actually rides the region (see `SearchEngine`).
    public var isFallbackEligible: Bool {
        switch kind {
        case .saveForLater, .newSnippet, .reminder, .event:
            return true
        case .customAction, .shortcut:
            guard let first = arguments.first else { return false }
            // A choice slot's content type is `.text` too, so the option set is
            // what tells a free-text slot from a picked one — a query can only
            // seed the keyboard, never a fixed-option or date/number step.
            return first.contentType == .text && first.options.isEmpty
        default:
            return false
        }
    }

    /// Whether this Action can be pinned as a **Favorite** (CONTEXT.md →
    /// Favorite). Everything in the indexed catalog is pinnable except a Pile
    /// entry: its main action *consumes* it — staging removes the entry from
    /// the Pile (CONTEXT.md → Stage) — so a pin would outlive its target on
    /// first use, leaving an invisible "ghost" holding one of the four grid
    /// slots. The App keys the Pin/Unpin affordance off this, and
    /// `SearchEngine.resolvableHomeIDs()` excludes ineligible ids so the
    /// launch reconciliation prunes any pin an older build allowed.
    ///
    /// Keyed off the row's **content** (`.pileEntry` is the entry's reference),
    /// not its kind: the Pile *page command row* wears the `.pile` kind too, and
    /// that durable command is pinnable like any other.
    public var isFavoriteEligible: Bool {
        isStandaloneRunnable
    }

    /// Whether this Action carries a **Pile entry**'s reference as its Result
    /// content — the row whose main action *consumes* it (staging removes it from
    /// the Pile, CONTEXT.md → Stage). Keyed off the row's **content**
    /// (`.pileEntry`), not its `.pile` kind: the Pile *page command row* wears the
    /// `.pile` kind too but is a durable command, not an entry.
    public var isPileEntry: Bool {
        if case .pileEntry = content { return true }
        return false
    }

    /// Whether this Action, run **standalone** (verb-first, no typed query), silently
    /// commits that absent query with **no UI** — so nothing observable happens. The
    /// one such shape is **Save for later**: its main action writes the raw typed
    /// query straight into the [[Pile]] (`.saveToPile`), so with no query there is
    /// nothing to save and nothing to see. Detected by the **outcome**, not the kind
    /// — `run()` with no input is `.saveToPile` — so the rule reads off what the
    /// action actually does. New Snippet is deliberately *not* here: though it too
    /// consumes the query as a Fallback, run standalone it opens the Snippet editor
    /// (`.composeSnippet`) seeded with the (empty) text — a real, useful verb-first
    /// action — so it stays a standalone run target. The argument-collecting captures
    /// (Reminder, Event) open a breadcrumb, and every other Action runs to an effect.
    public var isSilentQueryCapture: Bool {
        // Only an argument-less action consumes the query through its single-step
        // effect; an argument-collecting one produces its outcome from collected
        // values (its plain `run()` is the `.none` placeholder), so guard first —
        // the same caution `mainAction` takes before reading a single-step outcome.
        guard arguments.isEmpty else { return false }
        if case .saveToPile = run() { return true }
        return false
    }

    /// Whether running this Action **standalone** — verb-first from an [[Entry
    /// surface]], a Favorite card, an [[Actions widget]] / [[Action control]] button,
    /// or a `quickie://run/<id>` deeplink, with no typed query — does something. Two
    /// shapes fail it: a **Pile entry** (its run *consumes* it — a bound button dies
    /// after one tap) and a **silent query capture** (Save for later, which just
    /// writes the absent query into the Pile). Everything else — a Snippet, Quicklink,
    /// Shortcut, Custom Action, New Snippet (opens the editor), the argument-collecting
    /// captures, and every command row — runs to a real effect.
    ///
    /// The one predicate the standalone surfaces share so their "is this worth
    /// offering?" answer can never drift: favorite- and widget-eligibility both
    /// require it. A row's **Copy action deeplink** is close but not identical — it is
    /// withheld only from a silent query capture (its deeplink is a no-op), *not* from
    /// a Pile entry, whose deeplink stages (an effect) — so that verb is gated on
    /// `!isSilentQueryCapture` directly (the App), not on this compound predicate.
    public var isStandaloneRunnable: Bool {
        !isPileEntry && !isSilentQueryCapture
    }

    /// Whether this Action may be **chosen** for the [[Actions widget]] or the
    /// [[Action control]] (CONTEXT.md → Actions widget; ADR 0027): every Action that
    /// is `isStandaloneRunnable` — i.e. **not a Pile entry and not a silent query
    /// capture** (Save for later). A widget/control button runs its action with no
    /// typed query, so a Pile entry (consumed on first tap) and a Save for later
    /// (nothing to save) would both be dead buttons; every other enabled Action —
    /// New Snippet included, since it opens the editor — is a valid choice. (Disabled
    /// instances and kinds are already hidden from every surface, so the "enabled"
    /// half of the rule is enforced by the engine's catalog filtering, not here —
    /// this predicate is the pure per-Action shape half.)
    public var isWidgetEligible: Bool {
        isStandaloneRunnable
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
    /// Builds a **static (slot-less) Custom Action** (CONTEXT.md → Custom Action; ADR
    /// 0030): a resolved URL that opens directly, consuming no typed text and carrying
    /// no `{placeholder}` — the former Quicklink shape. It matches by name like any
    /// other Action and wears the link glyph (`kind: .quicklink`). The query-consuming,
    /// slotted behaviour is the same concept with arguments (`CustomActionDefinition`),
    /// which is how the App builds these from stored rows; this factory is the direct
    /// convenience the engine tests use to construct one.
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
            outputType: .url,
            // A Quicklink declares `.quicklink(id:)` content, not the bare `.url` its
            // open outcome would derive (ADR 0017): the id lets the long-press menu
            // add **Edit** (open the stored link in its create/edit form) on top of
            // the universal copy/share, which a value-only URL can't offer.
            content: .quicklink(id: id)
        ) { _ in .openURL(url) }
    }

    /// True when `template` carries at least one real `{name}` token — the
    /// validation the Quicklink editor uses to reject a templated URL, and the
    /// interim Custom Action editor uses to require one. An empty `{}` pair is not a
    /// token. The Custom Action factory enforces the same invariant via
    /// `CustomActionDefinition.tokenNames` (a definition with no token factories no
    /// Action); this stays the App-facing validator so a form can gate Save on it.
    public static func templateContainsPlaceholder(_ template: String) -> Bool {
        template.range(of: "\\{[^}]+\\}", options: .regularExpression) != nil
    }

    /// A Snippet: saved, reusable text whose main action is **Copy**
    /// (CONTEXT.md → Snippet). Self-contained — it ignores the typed text and
    /// always copies its stored `body` to the clipboard, which is what
    /// distinguishes it from a Pile entry (copy-out vs stage).
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
            outputType: .text,
            // A Snippet declares `.snippet(id:)` content, not the bare `.text` its
            // copy outcome would derive (ADR 0017): the id lets the long-press menu
            // add **Edit** (open the stored record in the editor) on top of the
            // universal copy/share, which a value-only `.text` row can't offer.
            content: .snippet(id: id)
        ) { _ in .copyText(body) }
    }

    /// The "Save for later" Fallback (CONTEXT.md → Pile, Fallback Action; ADR
    /// 0018): the silent capture that replaces "New Note". It always rides the
    /// bottom region and, when run, drops the user's literal typed text straight
    /// into the Pile — no editor, no confirm step. A permanent, disable-only
    /// Fallback like New Snippet.
    public static func saveForLater() -> Action {
        Action(
            id: saveForLaterID,
            kind: .saveForLater,
            title: "Save for later",
            aliases: ["later", "save", "pile"],
            inputTypes: [.text],
            outputType: .text
        ) { input in .saveToPile(text: input ?? "") }
    }

    /// The stable id of the "Save for later" capture — a permanent fallback-eligible
    /// built-in. Exposed so the App's Fallback list (which orders ids, not Actions)
    /// and the Core factory can never drift.
    public static let saveForLaterID = "builtin.save-for-later"
    /// The stable id of the "New Snippet" capture — the other permanent built-in.
    public static let newSnippetID = "builtin.new-snippet"

    /// The "New Snippet" Fallback (CONTEXT.md → Snippet, Fallback Action): the
    /// snippet counterpart to `newNote`. It rides the bottom region and, when run,
    /// opens the Snippet editor seeded with the typed text as the copy-out body,
    /// which the user titles and confirms before it is stored.
    public static func newSnippet() -> Action {
        Action(
            id: newSnippetID,
            kind: .newSnippet,
            title: "New Snippet",
            aliases: ["snippet", "clip", "save text"],
            inputTypes: [.text],
            outputType: .text
        ) { input in .composeSnippet(seed: input ?? "") }
    }

    /// A Shortcut Action (CONTEXT.md → Shortcut Action; issue #45, #46): runs one of
    /// the user's iOS Shortcuts by name. Registered solely by the Sync Shortcut
    /// import (ADR 0007) and matched by name like a Quicklink or Snippet. The id is
    /// derived from the case-folded name — the shortcut's stable identity — so a
    /// pinned Favorite or its Frecency stays attached across launches and re-syncs.
    ///
    /// `acceptsInput` decides the run shape (issue #46). Off (the import default):
    /// the row fires immediately with no input — its outcome is
    /// `.runShortcut(name:, input: nil)`. On: it declares **one optional `text`
    /// Argument** and runs through the breadcrumb (`MultiStepAction`), passing the
    /// collected value as the shortcut's input. Either way the outcome carries only
    /// the name (and input); the app performs the x-callback-url open at the edge.
    public static func shortcut(name: String, acceptsInput: Bool = false) -> Action {
        // The input Argument is **optional** (issue #46): the user can submit it empty
        // and still run the shortcut, so the breadcrumb never traps someone who has
        // nothing to type.
        let arguments = acceptsInput ? [Argument(label: "Input", contentType: .text, isOptional: true)] : []
        return Action(
            id: shortcutID(for: name),
            kind: .shortcut,
            title: name,
            // A shortcut that accepts input consumes text; one that doesn't is
            // self-contained (matches by name, consumes no typed text).
            inputTypes: acceptsInput ? [.text] : [],
            outputType: .text,
            arguments: arguments,
            // A Shortcut declares `.shortcut(name:)` content, not the `.none` its
            // run outcome would derive (ADR 0017): the name lets the long-press menu
            // add **Edit** — a deeplink into the Shortcuts app's editor
            // (`shortcuts://open-shortcut`) — even though a runnable row carries no
            // text to copy or share.
            content: .shortcut(name: name),
            effect: { _ in .runShortcut(name: name, input: nil) },
            // An empty (or whitespace-only) collected value reads as **no input** —
            // the same as an `acceptsInput`-off run — rather than an empty-string
            // input, so an unfilled optional step and a no-input shortcut behave alike.
            multiStepEffect: { values in
                let text = values.firstText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .runShortcut(name: name, input: (text?.isEmpty ?? true) ? nil : text)
            }
        )
    }

    /// The stable id of the Shortcut Action named `name` — the same derivation
    /// the `shortcut` factory uses, exposed so a surface that only holds the
    /// name (the Shortcuts page's per-row enablement toggle, issue #68) keys
    /// the exact id the engine filters by, and the two can never drift.
    public static func shortcutID(for name: String) -> String {
        "shortcut.\(name.lowercased())"
    }

    /// A Pile entry (CONTEXT.md → Pile; ADR 0018): a raw query text the user
    /// saved to deal with later. It has **no stored title** — `text` is the whole
    /// entry — but the saved text can be a large multi-line paste, and a result
    /// row is a one-line pill. So the *display* title is the first non-empty
    /// line, length-capped, while the full text rides as an alias: the matcher
    /// scores title and aliases alike, so the entry stays fuzzy-matched over its
    /// entire body ("searchable in Results" for a titleless blob), and every
    /// surface renders a normal row. Its main action stages the text (CONTEXT.md
    /// → Stage); the Action carries only the entry's identity, and the app
    /// resolves it at the edge.
    public static func pileEntry(
        id: String,
        text: String
    ) -> Action {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? text
        return Action(
            id: id,
            kind: .pile,
            title: String(firstLine.prefix(60)),
            aliases: [text],
            inputTypes: [],
            outputType: .text
        ) { _ in .stagePileEntry(id: id) }
    }

    /// The "Pile" command (CONTEXT.md → Pile; ADR 0018): opens the full-screen
    /// Pile **entries** page — pure content to view and act on (tap stages,
    /// swipe discards) — replacing "All Notes". Deliberately not a Settings
    /// command row: the entries are temporary, so their page is distinct from
    /// the Pile provider's settings page under the hub. Aliases later / saved
    /// so the deferred queries are always a few keystrokes away.
    public static func openPilePage() -> Action {
        Action(
            id: "builtin.pile-page",
            kind: .pile,
            title: "Pile",
            aliases: ["later", "saved", "saved for later"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.pile) }
    }

    /// The "Pile Settings" command (CONTEXT.md → Settings command row; ADR
    /// 0019): the Pile provider's typed route to its options-only settings page
    /// under the hub. Its own row, distinct from the "Pile" command above,
    /// because the Pile is the one provider whose typed name opens *content*
    /// (the temporary entries — the ADR 0018 carve-out) rather than its unified
    /// page: the entries page deliberately carries no options, so without this
    /// row a disabled Pile (issue #67) would be re-enableable only from the
    /// hub's Providers list — the lone provider breaking the typed-recovery
    /// promise every other Settings command row keeps.
    public static func openPileSettings() -> Action {
        Action(
            id: "builtin.pile-settings",
            kind: .managementPage,
            title: "Pile Settings",
            aliases: ["pile options", "save for later settings"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .pile)) }
    }

    /// The "All Snippets" command (CONTEXT.md → Snippet, Settings command row):
    /// the Snippets provider's typed row, deeplinking to the Snippets provider
    /// page under the hub.
    public static func openSnippetsLibrary() -> Action {
        Action(
            id: "builtin.snippets-library",
            kind: .snippet,
            title: "All Snippets",
            aliases: ["snippets", "snippet library", "browse snippets"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .snippets)) }
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
        ) { _ in .openPage(.settings(panel: nil)) }
    }

    /// The "Shortcuts" command (CONTEXT.md → Management page; issue #45):
    /// deeplinks to the Shortcuts provider page — the home for imported Shortcut
    /// Actions, with the per-row "accepts input" toggle and the Sync-Shortcut
    /// install/re-sync entry point — now reached through the hub (ADR 0019).
    public static func openShortcutsPage() -> Action {
        Action(
            id: "builtin.shortcuts-page",
            kind: .managementPage,
            title: "Shortcuts",
            aliases: ["shortcut", "sync shortcuts", "manage shortcuts"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .shortcuts)) }
    }

    /// The "Custom Actions" command (CONTEXT.md → Custom Action, Settings command
    /// row; ADR 0021, issue #94): deeplinks to the Custom Actions provider page under
    /// the hub — the authoring surface where a URL-template Action is created and
    /// edited — both slotted actions and static (slot-less) links, unified here (ADR
    /// 0030). Distinct from "Fallbacks", which orders the fallback region.
    public static func openCustomActionsPage() -> Action {
        Action(
            id: "builtin.custom-actions-page",
            kind: .managementPage,
            title: "Custom Actions",
            aliases: ["custom action", "url actions", "templates", "url templates", "links", "bookmarks"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .customActions)) }
    }

    /// The "Fallbacks" command (CONTEXT.md → Fallback list, Settings command
    /// row): deeplinks to the unified, reorderable Fallbacks provider page
    /// (Fallback queries + New Note + New Snippet) under the hub.
    public static func openFallbacksPage() -> Action {
        Action(
            id: "builtin.fallbacks-page",
            kind: .managementPage,
            title: "Fallbacks",
            aliases: ["fallback", "search engines", "manage fallbacks"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .fallbacks)) }
    }

    /// The "Calculator" command (CONTEXT.md → Settings command row; ADR 0019):
    /// the Calculator provider's typed row, deeplinking to its page under the
    /// hub. Brand-new — as a dynamic injector it never had a management row, so
    /// this is what makes the provider reachable (and, later, re-enableable) by
    /// typing its name. Distinct from a calculator *result*, which only appears
    /// when the query is a math expression.
    public static func openCalculatorPage() -> Action {
        Action(
            id: "builtin.calculator-page",
            kind: .managementPage,
            title: "Calculator",
            aliases: ["calc", "calculator settings", "unit conversion"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .calculator)) }
    }

    /// The "File Search" command (CONTEXT.md → Settings command row; ADR 0019):
    /// the File Search provider's typed row, deeplinking to its page under the
    /// hub — the second previously row-less dynamic injector to gain one.
    /// Distinct from "Search Files", which *enters* the scoped browsing context.
    ///
    /// The provider page is also where the user grants, lists, and revokes the
    /// folders Quickie may search: the former standalone Indexed Folders page
    /// (issue #49) folded into it, so this row carries its file-access aliases
    /// and is the single typed route to folder management.
    public static func openFileSearchPage() -> Action {
        Action(
            id: "builtin.file-search-page",
            kind: .managementPage,
            title: "File Search",
            aliases: ["file search settings", "folders", "indexed folders", "file access", "search folders"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .fileSearch)) }
    }

    /// The "Events" command (CONTEXT.md → Settings command row; ADR 0019): the
    /// Events capture provider's typed row, deeplinking to its page under the
    /// hub. Distinct from "New Event", which *starts a capture* rather than
    /// opening a page — so the capture provider, like the dynamic injectors,
    /// never had a typed route to its settings until this row.
    public static func openEventsPage() -> Action {
        Action(
            id: "builtin.events-page",
            kind: .managementPage,
            title: "Events",
            aliases: ["event settings", "calendar settings"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .events)) }
    }

    /// The "Reminders" command (CONTEXT.md → Settings command row; ADR 0019):
    /// the Reminders capture provider's typed row, deeplinking to its page under
    /// the hub — the reminder counterpart to `openEventsPage`, distinct from the
    /// "New Reminder" capture row.
    public static func openRemindersPage() -> Action {
        Action(
            id: "builtin.reminders-page",
            kind: .managementPage,
            title: "Reminders",
            aliases: ["reminder settings"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .reminders)) }
    }

    /// The "System" command (CONTEXT.md → System provider, Settings command row;
    /// ADR 0029): the umbrella provider's typed row, deeplinking to its Management
    /// page — the cascading Enabled toggle, the Reminders/Events navigation rows,
    /// and the two OS-integration built-ins. Kind-less like the other page commands
    /// so a disabled System stays reachable (and re-enableable) by typing its name.
    public static func openSystemPage() -> Action {
        Action(
            id: "builtin.system-page",
            kind: .managementPage,
            title: "System",
            aliases: ["system settings", "os", "integration"],
            inputTypes: [],
            outputType: .text
        ) { _ in .openPage(.settings(panel: .system)) }
    }

    /// The stable id of the **Open iOS Settings** System built-in (ADR 0029).
    public static let openIOSSettingsID = "builtin.system.open-ios-settings"

    /// **Open iOS Settings** (CONTEXT.md → System provider; ADR 0029): a permanent
    /// System built-in with **no arguments** that opens Quickie's own page in the
    /// iOS Settings app — the only Settings target iOS exposes (a query-driven
    /// "search Settings" is infeasible publicly or privately; recorded as such, do
    /// not re-propose). Opens `app-settings:`, the value of
    /// `UIApplication.openSettingsURLString`, kept as a literal so Core stays
    /// UIKit-free (the App's Paste permission hint opens the same destination via
    /// that UIKit constant). A plain command row (no breadcrumb), never
    /// fallback-eligible, disable-only.
    public static func openIOSSettings() -> Action {
        Action(
            id: openIOSSettingsID,
            kind: .system,
            title: "Open iOS Settings",
            // Deliberately no bare "settings" alias: it would tie the always-present
            // "Settings" command row for the exact query "settings" and could seize
            // the highlighted top result (the Settings hub is the expected match
            // there). "settings" still fuzzy-matches these aliases as a subsequence,
            // so typing it surfaces this row — just ranked below the Settings command.
            aliases: ["ios settings", "open settings", "open ios settings"],
            inputTypes: [],
            outputType: .url,
            content: ResultContent.none
        ) { _ in
            // `UIApplication.openSettingsURLString` is documented as "app-settings:";
            // hard-coded here so the pure Core never imports UIKit.
            .openURL(URL(string: "app-settings:")!)
        }
    }

    /// A file surfaced by File Search (CONTEXT.md → File Search; ADR 0015): a row
    /// whose main action opens the file. It carries **only** the file's
    /// Indexed-Folder `bookmarkID` and its `relativePath` within that folder — never
    /// a filesystem URL — so the Core stays pure; the app resolves the pair to a
    /// security-scoped URL and opens it. The id folds both so the same relative path
    /// under two granted folders is two distinct rows, and the title (matched
    /// against the query) is the file's display name, defaulting to the path's last
    /// component. Self-contained like a Snippet: it consumes no typed text and is
    /// not a Fallback.
    public static func file(
        bookmarkID: String,
        relativePath: String,
        displayName: String? = nil
    ) -> Action {
        let name = displayName ?? (relativePath as NSString).lastPathComponent
        return Action(
            id: "file.\(bookmarkID).\(relativePath)",
            kind: .file,
            title: name,
            subtitle: relativePath,
            inputTypes: [],
            outputType: .file
        ) { _ in .openFile(bookmarkID: bookmarkID, relativePath: relativePath) }
    }

    /// The "Search Files" command (CONTEXT.md → Search Files context; ADR 0014):
    /// the built-in command row that opens the scoped, uncapped file-browsing
    /// surface. Selecting it enters the context — never a chrome mode toggle — so its
    /// outcome is `.enterFileSearch`, which the app performs by scoping the input to
    /// the file index and showing the `[Search Files] ▸ …` breadcrumb. It matches by
    /// name/alias like any command row (and so is Favorite-eligible), and is distinct
    /// from "Indexed Folders", which manages *where* files come from rather than
    /// searching them.
    public static func searchFiles() -> Action {
        Action(
            id: "builtin.search-files",
            kind: .searchFiles,
            title: "Search Files",
            aliases: ["files", "find files", "browse files", "file search"],
            inputTypes: [],
            // `.text` like every other command row (Settings, Quicklinks, Indexed
            // Folders…): selecting it enters the scoped browsing context, it does not
            // *produce* a file — so it must not read as a file-typed source for a
            // future Argument chain (ADR 0011).
            outputType: .text
        ) { _ in .enterFileSearch }
    }

}
