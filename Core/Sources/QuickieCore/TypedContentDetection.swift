import Foundation

/// Recognizing the query as a *value* rather than a name (CONTEXT.md → Detected
/// result; ADR 0032): the pure parser behind the [[Computed]] provider's Open /
/// Message / Call / Email rows. It answers one question per type — *does the
/// **whole trimmed query** parse as exactly one URL / phone number / email
/// address?* — so a boosted row is only ever justified as "you typed a thing,
/// here's the thing", never fired on a substring of longer prose.
///
/// The three detectors are independent and non-arbitrating (CONTEXT.md → Detected
/// result): the Computed provider calls each behind its own toggle and emits rows
/// for every one that matches, so an ambiguous query surfaces every applicable
/// interpretation at once. Kept UIKit-free and regex-based (no `NSDataDetector`,
/// whose availability wobbles across platforms) so the whole thing runs under
/// `swift test` on any box.
public enum TypedContentDetector {
    /// Trailing punctuation the whole-query rule tolerates (CONTEXT.md → Detected
    /// result: "a single trailing punctuation mark tolerated"): sentence marks a
    /// user pastes with, `apple.com.` or `me@work.com,`. A single trailing one is
    /// stripped before parsing; `/`, `#`, and the like are **not** here because they
    /// carry meaning inside a URL.
    private static let toleratedTrailingPunctuation = Set(".,;:!?")

    /// Strips **at most one** tolerated trailing punctuation mark (above), the whole-
    /// query rule's single-punctuation allowance. Everything downstream parses the
    /// result, so `apple.com.` reads as `apple.com` while `apple.com/a.` loses only
    /// the sentence dot.
    private static func strippingTrailingPunctuation(_ query: String) -> String {
        guard let last = query.last, toleratedTrailingPunctuation.contains(last) else {
            return query
        }
        return String(query.dropLast())
    }

    /// The whole trimmed query as a **URL**, or `nil` (CONTEXT.md → Detected result).
    /// A schemed URL (`https://apple.com/x`) parses directly; a **bare domain**
    /// (`apple.com`, `www.apple.com/deals`) counts too — someone who types exactly
    /// `apple.com` means *go there* — and is normalized to `https://…`. Declines
    /// anything with interior whitespace (not one URL) or an `@` (that is the email
    /// detector's, not a userinfo URL) and any all-numeric dotted run (`3.14` is a
    /// number, not a host): the final label must be an alphabetic TLD of length ≥ 2.
    public static func url(in query: String) -> URL? {
        let candidate = strippingTrailingPunctuation(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !candidate.isEmpty,
              candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !candidate.contains("@") else { return nil }

        // Host + optional port/path/query/fragment, with or without an http(s)
        // scheme. The host is one-or-more dot-separated DNS labels ending in an
        // alphabetic TLD (≥ 2 chars), which is what tells `apple.com` from `3.14`.
        let pattern = #"^(?:https?://)?(?:[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:[/?#]\S*)?$"#
        guard candidate.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }

        // Normalize a bare domain to an absolute https URL so the row opens a real
        // destination; a query that already carries a scheme is used verbatim.
        let normalized = candidate.range(of: "^[a-z]+://", options: [.regularExpression, .caseInsensitive]) != nil
            ? candidate
            : "https://\(candidate)"
        guard let url = URL(string: normalized), url.host?.isEmpty == false else { return nil }
        return url
    }

    /// The whole trimmed query as an **email address**, or `nil` (CONTEXT.md →
    /// Detected result). A pragmatic `local@domain.tld` shape — the address must be
    /// the entire query, so `email me@work.com` (prose) never fires.
    public static func email(in query: String) -> String? {
        let candidate = strippingTrailingPunctuation(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        guard candidate.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return candidate
    }

    /// The inclusive digit-count bounds a phone number must fall inside — a local
    /// 7-digit number (`555-1212`) up to a full international one. Outside it, a run
    /// of digits is a plain number, not a phone.
    private static let phoneDigitRange = 7...15

    /// The whole trimmed query as a **phone number**, returning its display form
    /// (trimmed, single trailing punctuation removed) or `nil` (CONTEXT.md →
    /// Detected result). Accepts an optional leading `+` and the usual separators
    /// (spaces, `-`, `.`, `()`), so `555-1212`, `(555) 123-4567`, and
    /// `+1 555 123 4567` all read as one number while `call 555-1212` (prose) does
    /// not. The number of *digits* must land inside `phoneDigitRange`, which is what
    /// keeps `3.14` and a bare year like `2026` from firing.
    public static func phone(in query: String) -> String? {
        let candidate = strippingTrailingPunctuation(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let pattern = #"^\+?[0-9\s().\-]+$"#
        guard candidate.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let digits = candidate.filter(\.isNumber).count
        guard phoneDigitRange.contains(digits) else { return nil }
        return candidate
    }

    /// The `tel:` dial URL for a detected phone `display` string — digits plus a
    /// preserved leading `+`, dropping the presentation separators the dialer does
    /// not want. Exposed so the Computed provider (Call row) and any caller build
    /// the same URL.
    public static func telURL(forPhoneDisplay display: String) -> URL? {
        URL(string: "tel:\(dialableDigits(from: display))")
    }

    /// The `sms:` message URL for a detected phone `display` string — the Message
    /// row's counterpart to `telURL`.
    public static func smsURL(forPhoneDisplay display: String) -> URL? {
        URL(string: "sms:\(dialableDigits(from: display))")
    }

    /// The `mailto:` compose URL for a detected email `address`.
    public static func mailtoURL(forEmail address: String) -> URL? {
        URL(string: "mailto:\(address)")
    }

    /// Collapses a phone display form to what a `tel:`/`sms:` scheme wants: a leading
    /// `+` when present, then the bare digits.
    private static func dialableDigits(from display: String) -> String {
        let hasPlus = display.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        let digits = String(display.filter(\.isNumber))
        return hasPlus ? "+\(digits)" : digits
    }

    /// The **bare value** to copy or share for a Detected result row that opens
    /// `url` (CONTEXT.md → Detected result: rows "carry a bare value as Result
    /// content"). A phone / email row opens a `tel:` / `sms:` / `facetime:` /
    /// `mailto:` URL, but the value the user means is the number or address behind
    /// that scheme — so this returns the recipient (`tel:5551212` → `5551212`,
    /// `mailto:me@work.com` → `me@work.com`), dropping any `?subject=…` mail
    /// parameters. Returns `nil` for a web URL, whose own absolute string is already
    /// the bare value (`https://apple.com`), so the Open row copies the URL itself.
    /// Lives here because it is the exact inverse of the `tel`/`sms`/`mailto` URL
    /// builders above; the App calls it at the copy/share edge.
    public static func bareValue(forDetectedURL url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              ["tel", "sms", "facetime", "mailto"].contains(scheme) else { return nil }
        let recipient = String(url.absoluteString.dropFirst(scheme.count + 1)) // drop "scheme:"
        // A mailto may carry headers (`?subject=…`); the address is what precedes them.
        return recipient.split(separator: "?", maxSplits: 1).first.map(String.init) ?? recipient
    }
}
