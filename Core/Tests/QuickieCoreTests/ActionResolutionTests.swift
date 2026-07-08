import Foundation
import Testing
@testable import QuickieCore

// `SearchEngine.action(for:)` is the tap-equivalent lookup a `quickie://run/<id>`
// deeplink resolves against (CONTEXT.md → Bridged Action; issue #120). These
// tests pin its contract: a live Indexed Action resolves, and anything that no
// longer resolves — an unknown id, a disabled kind, a disabled instance — returns
// `nil` so the app degrades to plain Home rather than running a stale reference.
struct ActionResolutionTests {

    private func catalog() -> [Action] {
        [
            .quicklink(id: "github", title: "Open GitHub", url: URL(string: "https://github.com")!),
            .quicklink(id: "apple", title: "Open Apple", url: URL(string: "https://apple.com")!),
        ]
    }

    @Test("a live indexed action resolves by its id")
    func liveActionResolves() {
        let engine = SearchEngine(providers: [IndexedProvider(catalog: catalog(), id: .quicklinks)])
        #expect(engine.action(for: "github")?.id == "github")
    }

    @Test("an unknown id resolves to nil")
    func unknownIDResolvesNil() {
        let engine = SearchEngine(providers: [IndexedProvider(catalog: catalog(), id: .quicklinks)])
        #expect(engine.action(for: "nope") == nil)
    }

    @Test("a disabled kind's action no longer resolves")
    func disabledKindResolvesNil() {
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: catalog(), id: .quicklinks)],
            enablement: ProviderEnablement(disabled: [.quicklinks])
        )
        #expect(engine.action(for: "github") == nil)
    }

    @Test("a disabled instance no longer resolves")
    func disabledInstanceResolvesNil() {
        let engine = SearchEngine(
            providers: [IndexedProvider(catalog: catalog(), id: .quicklinks)],
            disabledInstances: ["github"]
        )
        #expect(engine.action(for: "github") == nil)
        // A sibling instance under the same live kind still resolves.
        #expect(engine.action(for: "apple")?.id == "apple")
    }
}
