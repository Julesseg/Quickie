import Foundation

/// The Share Extension's classification rules (CONTEXT.md → Share Extension;
/// ADR 0022) — pure functions with no SwiftData or UIKit dependency, so the
/// extension stays a thin shell and these run under the Linux `swift test`
/// gate. This slice (issue #101) carries the URL branch: naming the Quicklink
/// a shared URL becomes.
public enum ShareClassification {
    /// The default name for the Quicklink a shared URL becomes: the shared
    /// page title when one came along, else the URL's host with any bare
    /// `www.` dropped, else the URL string itself (issue #101 — the sheet
    /// pre-fills this; the user edits freely before saving).
    public static func quicklinkName(pageTitle: String?, url: URL) -> String {
        let title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Some apps hand the URL string back as the item's "title" — no better
        // than no title at all, so it falls through to the host default.
        if !title.isEmpty, title != url.absoluteString { return title }
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        if host.hasPrefix("www."), host.count > 4 {
            return String(host.dropFirst(4))
        }
        return host
    }

    /// The web URL a piece of shared plain text *is*, when the whole text
    /// parses as one (ADR 0022): shared text that is itself an `http(s)` link
    /// defaults to the URL branch — the "I shared a link" reading. Prose, a
    /// link buried in a sentence, or a non-web scheme is not one: the whole
    /// text must be a single `http(s)` URL with a host.
    public static func webURL(fromSharedText text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
