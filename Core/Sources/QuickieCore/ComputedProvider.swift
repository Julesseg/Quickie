import Foundation

/// The **boosted-dynamic** Provider whose rows are derived from the query text
/// *itself* rather than matched by name (CONTEXT.md → Computed; ADR 0032). It
/// folds two families under one provider:
///
/// - **Calculator** (issue #8) — a math expression or an offline unit conversion,
///   whose row **copies-and-stages** the answer so the user keeps calculating
///   (`2+2` → `4` → `4 * 3`).
/// - **Detected result** (ADR 0032) — the *whole trimmed query* recognized as a
///   URL, phone number, or email address, surfacing rows that act on it directly:
///   **Open** for a URL, **Message** + **Call** for a phone number, **Email** for
///   an address. Detection defers to `TypedContentDetector`, which only fires on a
///   whole-query match (never a substring of prose).
///
/// The provider the user sees is **Computed**, but its persisted `ProviderID` raw
/// value stays `.calculator` (renaming the stored identity would re-key kind-level
/// state — ADR 0032). Five per-type toggles gate its output — Math, Unit
/// conversion, URLs, Phone numbers, Email addresses, all default-on — so turning
/// the three detection toggles off restores the pre-detection Calculator exactly.
/// Every branch is independent and non-arbitrating: an ambiguous query
/// (`555-1212` reads as a phone number *and* as math) fires rows from every
/// applicable interpretation at once.
///
/// The SearchEngine floats a Dynamic Provider's results to the top region
/// unscored (boosted rank), so they read as top hits even though they are not name
/// matches (ADR 0008). It declines cleanly — returning `[]` — for anything that is
/// none of the above, so it never adds a spurious row.
public struct ComputedProvider: Provider {
    public let kind: ProviderKind = .dynamic

    /// The persisted identity stays `.calculator` (ADR 0032) even though the
    /// provider presents as Computed: renaming the raw value would re-key kind-level
    /// enablement, the same convention that kept `.quicklink` after ADR 0030.
    public let id: ProviderID? = .calculator

    private let math: Bool
    private let unitConversion: Bool
    private let url: Bool
    private let phone: Bool
    private let email: Bool

    /// Each flag mirrors one schema toggle (ADR 0020; ADR 0032) and suppresses
    /// exactly its rows. All default on so the Core stays fully functional and the
    /// App merely reflects the user's stored preferences; the three detection flags
    /// off (`url`/`phone`/`email`) reproduce the pre-detection Calculator exactly.
    public init(
        math: Bool = true,
        unitConversion: Bool = true,
        url: Bool = true,
        phone: Bool = true,
        email: Bool = true
    ) {
        self.math = math
        self.unitConversion = unitConversion
        self.url = url
        self.phone = phone
        self.email = email
    }

    public func candidates(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var rows: [Action] = []

        // Detected results lead so a phone number's **Message** row lands as the
        // highlighted result nearest the thumb (CONTEXT.md → Detected result: a
        // mis-Enter should text, never call), with **Call** above it. Each type is
        // gated by its own toggle and added independently — no arbitration.
        if url, let detected = TypedContentDetector.url(in: trimmed) {
            rows.append(openRow(url: detected))
        }
        if phone, let display = TypedContentDetector.phone(in: trimmed) {
            // Message first (index 0, nearest the thumb, the Highlighted result),
            // Call second (rendered above it).
            if let sms = TypedContentDetector.smsURL(forPhoneDisplay: display) {
                rows.append(detectedRow(id: "detect.phone.message", title: "Message", value: display, url: sms))
            }
            if let tel = TypedContentDetector.telURL(forPhoneDisplay: display) {
                rows.append(detectedRow(id: "detect.phone.call", title: "Call", value: display, url: tel))
            }
        }
        if email, let address = TypedContentDetector.email(in: trimmed),
           let mailto = TypedContentDetector.mailtoURL(forEmail: address) {
            rows.append(detectedRow(id: "detect.email", title: "Email", value: address, url: mailto))
        }

        // Calculator: math first — a query that evaluates but carries no operator is
        // just a bare number, not a calculation — otherwise an offline unit
        // conversion. Math and conversion are mutually exclusive, but either can
        // co-occur with a detected row (`555-1212` is both a phone and `-657`).
        if math, isCalculation(trimmed), let value = Calculator.evaluate(trimmed) {
            let answer = NumberFormat.string(value, maxFractionDigits: 10)
            rows.append(calculatorRow(id: "calc.math", title: answer, subtitle: trimmed, copying: answer))
        } else if unitConversion, let conversion = Units.convert(trimmed) {
            rows.append(calculatorRow(id: "calc.conversion", title: conversion.formatted, subtitle: trimmed, copying: conversion.formatted))
        }

        return rows
    }

    /// True when the query carries a *binary* arithmetic operator (or the `of`
    /// keyword) — the signal that the user is *calculating*, not merely typing a
    /// number. A leading `+`/`-` is a **sign**, not an operator, so a negative
    /// literal like `-5` reads as a bare number and declines, exactly as `42` does.
    /// That is what keeps a staged negative answer (`2 - 7` → `-5`) inert rather
    /// than re-triggering the Calculator on itself. `of` is matched on word
    /// boundaries so it triggers on "15% of 200" but not on words that merely
    /// contain the letters (`profile`, `off`).
    private func isCalculation(_ query: String) -> Bool {
        for (offset, char) in query.enumerated() {
            if "*/^%()".contains(char) { return true }
            if offset > 0 && "+-".contains(char) { return true }
        }
        return query.range(of: "\\bof\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Builds a **Calculator** row: title the answer, subtitle the expression, main
    /// action copies the answer *and* stages it back into the input (CONTEXT.md →
    /// main action). Declares `.number` content, *not* derived from the copy-text
    /// outcome (ADR 0017).
    private func calculatorRow(id: String, title: String, subtitle: String, copying copy: String) -> Action {
        Action(
            id: id,
            kind: .calculator,
            title: title,
            subtitle: subtitle,
            inputTypes: [],
            outputType: .number,
            content: .number
        ) { _ in .copyAndStage(text: copy) }
    }

    /// The **Open** row for a detected URL: its main action opens the URL, and it
    /// carries the URL as a bare `.url` value — the universal copy/share menu, no
    /// Edit (CONTEXT.md → Detected result), exactly a Calculator result's manners.
    private func openRow(url: URL) -> Action {
        detectedRow(id: "detect.url", title: "Open", value: url.absoluteString, url: url)
    }

    /// A **Detected result** row (Open / Message / Call / Email): a boosted row that
    /// resolves the query by opening `url` when run, showing the acted-on `value` as
    /// its subtitle and carrying a bare `.url` value so the long-press menu offers
    /// the universal copy/share (no Edit — it is a value, not a stored record). The
    /// value the menu copies is the bare thing the user typed: the Open row's own URL,
    /// and — for a `tel:`/`sms:`/`mailto:` row — the phone number or email behind the
    /// scheme, reduced by `TypedContentDetector.bareValue(forDetectedURL:)` at the
    /// copy/share edge. Wears the Computed provider's badge (`kind: .calculator`),
    /// like every row the provider contributes.
    private func detectedRow(id: String, title: String, value: String, url: URL) -> Action {
        Action(
            id: id,
            kind: .calculator,
            title: title,
            subtitle: value,
            inputTypes: [],
            outputType: .url,
            content: .url
        ) { _ in .openURL(url) }
    }
}
