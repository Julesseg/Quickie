import Foundation
@testable import QuickieCore

extension Action {
    /// The default web-search Fallback, as the app seeds it (ADR 0021, issue #114): an
    /// ordinary, deletable, one-Argument **Custom Action** whose free-text first slot
    /// makes it fallback-*eligible* by shape — no flag, no privileged built-in, no
    /// bespoke "Fallback query" type. A test convenience so the many suites that need
    /// "a fallback that consumes the query" read clearly and share one id
    /// (`builtin.web-search`); wire it into a `SearchEngine`'s `enabledFallbacks` to
    /// make it actually ride the region.
    static func webSearchFallback(
        template: String = "https://duckduckgo.com/?q={query}"
    ) -> Action {
        CustomActionDefinition(
            name: "Search the web",
            aliases: ["search", "google", "ddg"],
            template: template
        ).makeAction(id: "builtin.web-search")!
    }

    /// The shared id of the test web-search fallback, so suites can enable it without
    /// hard-coding the string in several places.
    static let webSearchFallbackID = "builtin.web-search"
}
