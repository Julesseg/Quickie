import Foundation
import Testing
@testable import QuickieCore

@Suite("Default Quicklink seeds")
struct QuicklinkSeedTests {
    @Test("the default Quicklinks carry fixed seed.link.* ids in most-important-first order")
    func seedIDsAreFixedAndOrdered() {
        #expect(QuicklinkSeed.all.map(\.id) == [
            "seed.link.youtube", "seed.link.gmail", "seed.link.github",
        ])
    }

    @Test("every seed URL parses and carries no {placeholder} (a Quicklink is static)")
    func seedURLsAreStaticAndValid() {
        for seed in QuicklinkSeed.all {
            #expect(URL(string: seed.urlString) != nil, "\(seed.id) has an unparseable URL")
            #expect(
                !Action.templateContainsPlaceholder(seed.urlString),
                "\(seed.id) carries a {placeholder} — a Quicklink must be static"
            )
        }
    }

    @Test("each seed builds a matchable Quicklink Action under its fixed id")
    func seedsBuildQuicklinkActions() {
        for seed in QuicklinkSeed.all {
            let action = Action.quicklink(
                id: seed.id,
                title: seed.title,
                aliases: seed.alias.map { [$0] } ?? [],
                url: URL(string: seed.urlString)!
            )
            #expect(action.id == seed.id)
            #expect(action.kind == .quicklink)
            #expect(action.title == seed.title)
        }
    }
}
