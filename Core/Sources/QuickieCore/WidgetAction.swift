import Foundation

/// How a widget-surface button executes its Action (ADR 0025; ADR 0027) — the
/// **three-way split** that runs an Action's main action with as little Quickie as
/// possible. A button behaves exactly like tapping the Action's result row, minus
/// any Quickie UI the row never showed anyway:
///
/// - `copySnippet` — **in-place**: the widget intent writes the pasteboard with no
///   app launch. It carries only the Snippet's id; the intent reads the body fresh
///   from the shared App Group store *at run time*, so a stale widget snapshot can
///   never copy stale text.
/// - `handOff` — **direct**: the widget opens the URL straight from its process —
///   a Quicklink's link in the browser, or a no-input Shortcut's
///   `shortcuts://x-callback-url` run (built by `ShortcutRun.runURL`, so the
///   `quickie://` callbacks land in the app unchanged and output reinjection works
///   exactly as an in-app run).
/// - `openApp` — **tap-equivalent**: anything needing input or in-app UI (a quick
///   capture, a slotted Custom Action, Search Files, a text-consuming capture, a
///   Pile entry's stage) opens the app via `quickie://run/<id>` (issue #120); an
///   id that no longer resolves degrades to clean Home, never an error.
///
/// The classification is a pure function of the Action's shape, kept in Core
/// (rather than decided in the widget or at the app edge) so it is `swift test`-
/// covered beside the deeplink parse (ADR 0024) and every out-of-process surface —
/// the Favorites widget, the Actions widget, the Action control — can never
/// disagree about what a button does.
public enum WidgetExecution: Equatable, Sendable, Codable {
    case copySnippet(id: String)
    case handOff(url: URL)
    case openApp

    /// Classifies an Action into its widget execution. Total — every Action gets
    /// a lane, and the unknown/none shapes land on `openApp`, the lane that can
    /// degrade gracefully (a `quickie://run/<id>` the app resolves live).
    public static func classify(_ action: Action) -> WidgetExecution {
        // A declared Argument means the run collects input through the breadcrumb
        // — in-app UI by definition (an accepts-input Shortcut, every Custom
        // Action, the quick captures) — so the button opens the app tap-equivalently.
        guard action.arguments.isEmpty else { return .openApp }
        // A Snippet copies in-place, by reference: the id (not the body) rides the
        // snapshot so the copy always reads the current text.
        if case .snippet(let id) = action.content { return .copySnippet(id: id) }
        switch action.run() {
        case .openURL(let url):
            // A Quicklink's static URL: the browser opening *is* the main action.
            return .handOff(url: url)
        case .runShortcut(let name, let input):
            // A no-input Shortcut: fire the same x-callback run the app would open,
            // so callbacks (and output reinjection) land in Quickie unchanged.
            return .handOff(url: ShortcutRun.runURL(name: name, input: input))
        default:
            // Everything else needs the app: text-consuming captures (Save for
            // later, New Snippet), a Pile entry's stage, command rows, and any
            // future outcome — `openApp` is the safe, gracefully-degrading lane.
            return .openApp
        }
    }
}

/// One Action as a widget surface renders and runs it (ADR 0025; ADR 0027): a small
/// **denormalized** projection — id, title, glyph, kind, and the classified
/// execution with its hand-off payload — so a widget draws and acts from the
/// snapshot alone, never opening SwiftData to render. The glyph is the provider
/// badge's SF Symbol name, denormalized by the app (the symbol lookup lives at the
/// App edge beside its tints); the kind rides along so the widget picks the badge
/// tint and the projection stays explainable.
///
/// This is the **one shared shape** both projections use — the Favorites widget's
/// pinned-grid snapshot (`FavoritesWidgetSnapshot`) and the eligible-action catalog
/// the Actions widget and Action control join their configured ids against
/// (`EligibleActionCatalog`) — so the two surfaces render one cell language and can
/// never drift onto different denormalizations (ADR 0027).
public struct WidgetAction: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    /// The provider badge's SF Symbol name, as the app's badge renders it.
    public let glyph: String
    public let kind: ActionKind
    public let execution: WidgetExecution

    public init(id: String, title: String, glyph: String, kind: ActionKind, execution: WidgetExecution) {
        self.id = id
        self.title = title
        self.glyph = glyph
        self.kind = kind
        self.execution = execution
    }

    /// Denormalizes an Action into its snapshot item, classifying its execution —
    /// the one derivation the app's snapshot writers use, so a projection can't
    /// drift from the classification. The glyph is passed in because the symbol
    /// lookup is App vocabulary (it lives beside the badge tints), not Core's.
    public init(action: Action, glyph: String) {
        self.init(
            id: action.id,
            title: action.title,
            glyph: glyph,
            kind: action.kind,
            execution: .classify(action)
        )
    }
}
