import AppIntents
import QuickieCore

/// The App Intents shell over the **Bridged Action** set (CONTEXT.md → Bridged
/// Action; ADR 0024; issue #122): one `AppEntity` with a dynamic query, driven by a
/// single parameterized App Shortcut ("Run <name> with Quickie"), so each member of
/// the derived set — Favorites ∪ Custom Actions, minus anything Disabled — surfaces
/// individually in Siri and Spotlight without a hand-curated shortcut per Action.
///
/// Everything *decidable* lives in Core: the membership rule is
/// `SearchEngine.bridgedActions()` (`swift test`-covered), and invocation rides the
/// slice-1 `quickie://run/<id>` grammar. This file is the thin Apple layer — App
/// Intents is app-process and Apple-only — and it reads the derived set from the
/// published `BridgedActionStore` snapshot so the query works even when the system
/// runs it out of process.

/// One value of the parameterized "Run <name>" App Shortcut — a member of the
/// bridged set. It mirrors `QuickieCore.BridgedAction`'s two fields: the stable id
/// (the `quickie://run/<id>` target and the entity identity) and the title Siri and
/// Spotlight show. Nothing about *what running it does* lives here — the app resolves
/// that live through the id, so a stale entity degrades to Home rather than erroring.
struct BridgedActionEntity: AppEntity {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(_ action: BridgedAction) {
        self.init(id: action.id, title: action.title)
    }

    /// How the parameter's *type* reads in the Shortcuts editor and Siri.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Quickie Action")
    }

    /// How one member reads wherever it is shown — its Action title.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static var defaultQuery = BridgedActionQuery()
}

/// The **dynamic** query behind the entity (ADR 0024): it enumerates the current
/// bridged set from the published `BridgedActionStore` snapshot, so Siri/Spotlight
/// offer exactly the Favorites and Custom Actions live *now*. `updateAppShortcutParameters()`
/// (fired by the app on every set change) is what asks the system to re-run this.
struct BridgedActionQuery: EntityQuery {
    /// Resolve specific ids the system already holds — filtered to the ones still in
    /// the snapshot. A dropped id simply isn't returned; the run path additionally
    /// guards staleness by resolving `quickie://run/<id>` live.
    func entities(for identifiers: [String]) async throws -> [BridgedActionEntity] {
        let live = BridgedActionStore.load()
        let wanted = Set(identifiers)
        return live.filter { wanted.contains($0.id) }.map { BridgedActionEntity($0) }
    }

    /// Every current member — the options the parameterized phrase and the Shortcuts
    /// editor present.
    func suggestedEntities() async throws -> [BridgedActionEntity] {
        BridgedActionStore.load().map { BridgedActionEntity($0) }
    }
}

/// The single parameterized intent (ADR 0024): "Run <name> with Quickie". Invocation
/// is **tap-equivalent** — it opens the slice-1 `quickie://run/<id>` deeplink through
/// the shared `DeeplinkInbox`, exactly the path a headline foreground verb and the
/// entry surfaces use, so the app behaves as if the user tapped that Action's result
/// row (a Favorite runs its main action; a Custom Action starts its breadcrumb). A
/// reference that no longer resolves — unpinned, deleted, or disabled since the system
/// last synced — degrades to plain Home, handled entirely by `handleDeeplink`'s live
/// `action(for:)` lookup, so this intent needs no staleness logic of its own.
struct RunBridgedActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Quickie Action"
    static let description = IntentDescription(
        "Run one of your Quickie Favorites or Custom Actions."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Action")
    var target: BridgedActionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Tap-equivalent run through the one inbound door (ADR 0024): deposit the
        // Core-built `quickie://run/<id>` for `RootView` to dispatch through the same
        // `QuickieDeeplink.parse → handleDeeplink` the root `onOpenURL` runs. The app
        // resolves the id against the live catalog, degrading to Home if it's stale.
        DeeplinkInbox.shared.deposit(QuickieDeeplink.runURL(id: target.id))
        return .result()
    }
}
