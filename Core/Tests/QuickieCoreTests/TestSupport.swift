import Foundation
@testable import QuickieCore

extension Action {
    /// The default web-search Fallback query, as the app seeds it (ADR 0013): an
    /// ordinary, deletable Fallback query — no longer a privileged built-in. A
    /// test convenience so the many suites that need "a fallback that consumes the
    /// query" read clearly and share one id (`builtin.web-search`).
    static func webSearchFallback(
        template: String = "https://duckduckgo.com/?q={query}"
    ) -> Action {
        .fallbackQuery(
            id: "builtin.web-search",
            title: "Search the web",
            aliases: ["search", "google", "ddg"],
            template: template
        )!
    }
}
