import Foundation

/// The Share Extension's classification rules (CONTEXT.md → Share Extension;
/// ADR 0022) — pure functions with no SwiftData or UIKit dependency, so the
/// extension stays a thin shell and these run under the Linux `swift test`
/// gate. This slice (issue #101) carries the URL branch: naming the static Custom
/// Action a shared URL becomes (ADR 0030 — the former Quicklink).
public enum ShareClassification {
    /// The branch a shared payload takes once the extension has unpacked it
    /// (ADR 0022): save it as a static Custom Action seeded from a URL (the `.quicklink`
    /// case — the former Quicklink, ADR 0030), as a Snippet/Pile seeded from text, or
    /// refuse an empty payload.
    ///
    /// The static-link branch carries a `textFallback`: when the URL came from
    /// plain text that is *itself* a web URL (issue #103), it is the original
    /// shared string, and the sheet — defaulting to the link — offers a switch
    /// to read it as text instead. For a genuine `public.url` attachment the URL
    /// is unambiguous, so the fallback is `nil` and no toggle is offered.
    public enum Route: Equatable {
        case quicklink(URL, textFallback: String?)
        case text(String)
        case unsupported
    }

    /// Decide which branch a shared payload takes from the pieces the extension
    /// managed to load (ADR 0022). A genuine shared/selected string
    /// (`sharedText` — a `public.plain-text` attachment or the item's
    /// `attributedContentText`) **wins over the page `attachedURL`**:
    /// highlight-and-share in Safari, Books, or Notes hands the extension the
    /// selected text *and* the page's link, but the user's intent is the text
    /// they highlighted — the link is incidental. A shared string that is
    /// *itself* a web URL still takes the Quicklink branch (the "I shared a
    /// link" reading, `webURL(fromSharedText:)`), so a plain page share — whose
    /// only "text", if any, is the URL string — still becomes a Quicklink; so
    /// does a page share carrying no selection at all. That text-derived
    /// Quicklink keeps the original string as its `textFallback` so the sheet
    /// can switch to the text branch (issue #103); a genuine `public.url`
    /// attachment has no fallback and no toggle. An empty payload is
    /// unsupported. File-URL refusal stays in the shell (it owns the message).
    public static func route(sharedText: String?, attachedURL: URL?) -> Route {
        if let text = sharedText,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let url = webURL(fromSharedText: text) {
                return .quicklink(url, textFallback: text)
            }
            return .text(text)
        }
        if let url = attachedURL {
            return .quicklink(url, textFallback: nil)
        }
        return .unsupported
    }

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

    /// The default title for the [[Snippet]] a piece of shared plain text
    /// becomes (ADR 0022; issue #102): the first non-empty line of the text,
    /// trimmed and length-capped to ~40 characters. A Snippet is titled,
    /// reusable text, so the sheet pre-fills this and the user edits it freely
    /// before saving; the [[Pile]] alternative is titleless and needs none of
    /// it. The whole shared text still rides along as the Snippet body — this
    /// derives only the one-line handle. The cap prefers a word boundary (a
    /// long first line is cut back to the last whitespace within the limit
    /// rather than sliced mid-word) and hard-cuts only when the first word
    /// alone overruns.
    public static func snippetTitle(fromSharedText text: String, maxLength: Int = 40) -> String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        guard firstLine.count > maxLength else { return firstLine }

        let capped = firstLine.prefix(maxLength)
        // Back up to the last word boundary so a word isn't sliced in half;
        // fall through to the hard cut when the first word already overruns.
        if let lastSpace = capped.lastIndex(where: \.isWhitespace) {
            let atBoundary = capped[..<lastSpace].trimmingCharacters(in: .whitespacesAndNewlines)
            if !atBoundary.isEmpty { return atBoundary }
        }
        return String(capped)
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
