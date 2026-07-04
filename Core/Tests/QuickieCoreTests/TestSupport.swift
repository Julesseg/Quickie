import Foundation
@testable import QuickieCore

extension Action {
    /// The default web-search Fallback, as the app seeds it (ADR 0021): an ordinary,
    /// deletable, fallback-flagged one-Argument **Custom Action** — no longer a
    /// privileged built-in, and no longer a bespoke "Fallback query" type. A test
    /// convenience so the many suites that need "a fallback that consumes the query"
    /// read clearly and share one id (`builtin.web-search`).
    static func webSearchFallback(
        template: String = "https://duckduckgo.com/?q={query}"
    ) -> Action {
        CustomActionDefinition(
            name: "Search the web",
            aliases: ["search", "google", "ddg"],
            template: template,
            isFallback: true
        ).makeAction(id: "builtin.web-search")!
    }
}
