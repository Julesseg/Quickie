import Foundation
import Testing
@testable import QuickieCore

// The Favorites widget is a **projection, not a second engine** (ADR 0025; issue
// #126): the app writes a small denormalized snapshot of the pinned Favorites into
// the App Group, and the widget renders from the snapshot alone. Two of the ADR's
// three pure pieces live here — the **in-place / hand-off / open classification**
// (how a widget button executes a Favorite with as little Quickie as possible) and
// the **snapshot codec** (what the app writes and the widget reads) — covered by
// `swift test` so the whole grammar is exercised without a device. The third piece,
// the frecency outbox merge, has its own suite (`WidgetRunOutboxTests`).
struct FavoritesWidgetSnapshotTests {

    // MARK: Classification — in-place copy

    @Test("a Snippet classifies as in-place copy, carrying the id — never the body text")
    func snippetCopiesInPlace() {
        let action = Action.snippet(id: "snippet.abc", title: "Address", body: "1 Main St")
        // The intent reads the body fresh from the shared store at run time, so the
        // classification carries only the reference — a stale snapshot can never
        // copy stale text.
        #expect(WidgetExecution.classify(action) == .copySnippet(id: "snippet.abc"))
    }

    // MARK: Classification — direct hand-off

    @Test("a Quicklink classifies as a direct hand-off to its URL — no app launch")
    func quicklinkHandsOff() {
        let url = URL(string: "https://docs.example")!
        let action = Action.quicklink(id: "ql.docs", title: "Docs", url: url)
        #expect(WidgetExecution.classify(action) == .handOff(url: url))
    }

    @Test("a no-input Shortcut hands off to the x-callback run URL, callbacks intact")
    func shortcutHandsOffViaXCallback() {
        let action = Action.shortcut(name: "Start Workout")
        // The exact URL the in-app run opens (`ShortcutRun.runURL`), so a Shortcut's
        // `quickie://` callbacks land in the app unchanged and output reinjection
        // works exactly as an in-app run.
        #expect(WidgetExecution.classify(action) == .handOff(url: ShortcutRun.runURL(name: "Start Workout", input: nil)))
    }

    // MARK: Classification — input-needing kinds open the app

    @Test("an accepts-input Shortcut opens the app — its run shows the breadcrumb")
    func inputShortcutOpensApp() {
        let action = Action.shortcut(name: "Translate", acceptsInput: true)
        #expect(WidgetExecution.classify(action) == .openApp)
    }

    @Test("a Custom Action opens the app — its run collects Arguments in-app")
    func customActionOpensApp() {
        let action = CustomActionDefinition(
            name: "Search",
            template: "https://x.example/?q={query}"
        ).makeAction(id: "ca.search")!
        #expect(WidgetExecution.classify(action) == .openApp)
    }

    @Test("the quick captures open the app — a breadcrumb needs in-app UI")
    func capturesOpenApp() {
        #expect(WidgetExecution.classify(.newReminder()) == .openApp)
        #expect(WidgetExecution.classify(.newEvent()) == .openApp)
    }

    @Test("Search Files opens the app — the scoped context is in-app UI")
    func searchFilesOpensApp() {
        #expect(WidgetExecution.classify(.searchFiles()) == .openApp)
    }

    @Test("the text-consuming captures open the app — they need the typed query")
    func textConsumingCapturesOpenApp() {
        // Save for later and New Snippet consume the raw typed text through their
        // effect rather than a declared Argument, so their shape alone doesn't say
        // "input-needing" — the outcome classification must still send them in-app.
        #expect(WidgetExecution.classify(.saveForLater()) == .openApp)
        #expect(WidgetExecution.classify(.newSnippet()) == .openApp)
    }

    @Test("a Pile entry opens the app — staging reinjects into the input")
    func pileEntryOpensApp() {
        #expect(WidgetExecution.classify(.pileEntry(id: "pile.1", text: "call bank")) == .openApp)
    }

    @Test("a management command opens the app — its page is in-app UI")
    func managementCommandOpensApp() {
        #expect(WidgetExecution.classify(.openSettings()) == .openApp)
    }

    // MARK: The denormalized snapshot item

    @Test("a snapshot item denormalizes id, title, kind, and the classified execution")
    func itemDenormalizesFromAction() {
        let url = URL(string: "https://docs.example")!
        let action = Action.quicklink(id: "ql.docs", title: "Docs", url: url)
        let item = WidgetFavorite(action: action, glyph: "link")
        #expect(item.id == "ql.docs")
        #expect(item.title == "Docs")
        #expect(item.glyph == "link")
        #expect(item.kind == .quicklink)
        #expect(item.execution == .handOff(url: url))
    }

    // MARK: Codec — what the app writes, the widget reads

    private func item(_ id: String, kind: ActionKind = .quicklink, execution: WidgetExecution = .openApp) -> WidgetFavorite {
        WidgetFavorite(id: id, title: "Title \(id)", glyph: "link", kind: kind, execution: execution)
    }

    @Test("the snapshot round-trips through the codec, order preserved")
    func snapshotRoundTrips() {
        let favorites = [
            item("a", kind: .snippet, execution: .copySnippet(id: "snippet.a")),
            item("b", execution: .handOff(url: URL(string: "https://x.example")!)),
            item("c", kind: .customAction),
        ]
        let data = FavoritesWidgetSnapshot.encode(favorites)
        #expect(FavoritesWidgetSnapshot.decode(data) == favorites)
    }

    @Test("decoding nothing or garbage yields an empty snapshot — never an error")
    func decodeDegradesToEmpty() {
        #expect(FavoritesWidgetSnapshot.decode(nil) == [])
        #expect(FavoritesWidgetSnapshot.decode(Data("not json".utf8)) == [])
    }

    @Test("the snapshot is capped at the grid's four — extras never ride along")
    func snapshotCapsAtFour() {
        let five = ["a", "b", "c", "d", "e"].map { item($0) }
        let decoded = FavoritesWidgetSnapshot.decode(FavoritesWidgetSnapshot.encode(five))
        // The cap keeps pin order: the first four survive, the fifth is dropped —
        // mirroring the in-app grid, which never renders a fifth card.
        #expect(decoded.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test("an empty snapshot encodes and decodes as empty — the zero-pins placeholder state")
    func emptySnapshotRoundTrips() {
        #expect(FavoritesWidgetSnapshot.decode(FavoritesWidgetSnapshot.encode([])) == [])
    }
}
