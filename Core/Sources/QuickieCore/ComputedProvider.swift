import Foundation

/// The **boosted-dynamic** Provider whose rows are derived from the query text
/// *itself* rather than matched by name (CONTEXT.md → Computed; ADR 0032). It
/// folds two families under one provider:
///
/// - **Calculator** (issue #8) — a math expression or an offline unit conversion,
///   whose row **copies-and-stages** the answer so the user keeps calculating
///   (`2+2` → `4` → `4 * 3`).
/// - **Date & time** (issues #210/#212/#213; ADR 0036) — a relative-arithmetic
///   phrase ("3 weeks from friday"), an until/since question ("days until dec
///   25"), a timezone conversion ("9am PST in tokyo"), or a timestamp decode
///   ("unix 1735689600"), parsed by the table-driven `DateGrammar` against the
///   injected clock and calendar. Staging follows the answer's kind (CONTEXT.md
///   → Stage): a date, time, or timestamp answer is terminal, so its row is
///   copy-only with `.date` content, formatted per device locale; a count
///   answer is a number, so its row is a full Calculator row — copy-and-stage,
///   `.number` content.
/// - **Detected result** (ADR 0032; issue #217) — the *whole trimmed query*
///   recognized as a URL, phone number, email address, or hex color, surfacing rows
///   that act on it directly: **Open** for a URL, **Message** + **Call** for a phone
///   number, **Email** for an address, **Copy** for a color (terminal under the
///   Stage rule, so copy-only, its swatch tinting the row's leading glyph).
///   Detection defers to `TypedContentDetector`, which only fires on a whole-query
///   match (never a substring of prose).
///
/// The provider the user sees is **Computed**, but its persisted `ProviderID` raw
/// value stays `.calculator` (renaming the stored identity would re-key kind-level
/// state — ADR 0032). Seven per-type toggles gate its output — Math, Unit
/// conversion, Date & time, URLs, Phone numbers, Email addresses, Colors, all
/// default-on — so turning the four detection toggles off restores the
/// pre-detection Calculator exactly. Every branch is independent and
/// non-arbitrating: an ambiguous query (`555-1212` reads as a phone number *and* as
/// math) fires rows from every applicable interpretation at once.
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
    private let dateTime: Bool
    private let url: Bool
    private let phone: Bool
    private let email: Bool
    private let color: Bool
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Each flag mirrors one schema toggle (ADR 0020; ADR 0032) and suppresses
    /// exactly its rows. All default on so the Core stays fully functional and the
    /// App merely reflects the user's stored preferences; the four detection flags
    /// off (`url`/`phone`/`email`/`color`) reproduce the pre-detection Calculator
    /// exactly.
    ///
    /// The `calendar` and `now` clock feed the Date & time grammar (issue #210) —
    /// injected so "today" is testable; the defaults read the device, live, on
    /// every query.
    public init(
        math: Bool = true,
        unitConversion: Bool = true,
        dateTime: Bool = true,
        url: Bool = true,
        phone: Bool = true,
        email: Bool = true,
        color: Bool = true,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.math = math
        self.unitConversion = unitConversion
        self.dateTime = dateTime
        self.url = url
        self.phone = phone
        self.email = email
        self.color = color
        self.calendar = calendar
        self.now = now
    }

    public func candidates(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // The device language — read off the injected calendar's locale —
        // picks the accepted keyword tables (ADR 0036; issue #211): English,
        // the dual-accept floor, plus the device language's table when we ship
        // one. The same tables feed the date grammar and the Units connectors.
        let tables = DateKeywordTable.tables(for: calendar.locale ?? Locale(identifier: "en_US"))

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
        if color, let detected = TypedContentDetector.color(in: trimmed) {
            rows.append(colorRow(detected))
        }

        // Calculator: math first — a query that evaluates but carries no operator is
        // just a bare number, not a calculation — otherwise an offline unit
        // conversion. Math and conversion are mutually exclusive, but either can
        // co-occur with a detected row (`555-1212` is both a phone and `-657`).
        if math, isCalculation(trimmed), let value = Calculator.evaluate(trimmed) {
            let answer = NumberFormat.string(value, maxFractionDigits: 10)
            rows.append(calculatorRow(id: "calc.math", title: answer, subtitle: trimmed, copying: answer))
        } else if unitConversion, let conversion = Units.convert(trimmed, tables: tables) {
            rows.append(calculatorRow(id: "calc.conversion", title: conversion.formatted, subtitle: trimmed, copying: conversion.formatted))
        }

        // Date & time (issues #210/#212/#213): relative arithmetic answers a
        // *date*, a timezone conversion a *time*, and a timestamp decode a
        // *timestamp* — terminal values, so their rows are copy-only — while an
        // until/since count answers a *number*, whose row gets full Calculator
        // manners (staging follows the answer's kind, CONTEXT.md → Stage).
        // Another independent branch: a query readable as a date question *and*
        // anything above fires every applicable row.
        if dateTime {
            for answer in DateGrammar.answers(for: trimmed, tables: tables, calendar: calendar, now: now()) {
                switch answer {
                case .date(let date):
                    let formatted = DateGrammar.formatted(date, calendar: calendar)
                    rows.append(dateRow(id: "date.relative", title: formatted, subtitle: trimmed))
                case .count(let count):
                    let text = NumberFormat.string(Double(count), maxFractionDigits: 0)
                    rows.append(calculatorRow(id: "date.count", title: text, subtitle: trimmed, copying: text))
                case .time(let instant, let zone, let dayOffset):
                    let formatted = DateGrammar.formattedTime(instant, in: zone, dayOffset: dayOffset, calendar: calendar)
                    rows.append(dateRow(id: "date.timezone", title: formatted, subtitle: trimmed))
                case .timestamp(let instant):
                    let formatted = DateGrammar.formattedTimestamp(instant, calendar: calendar)
                    rows.append(dateRow(id: "date.timestamp", title: formatted, subtitle: trimmed))
                }
            }
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

    /// Builds a **Date & time** date-answer row (issue #210): title the
    /// locale-formatted date, subtitle the phrase that asked for it, main action
    /// **copy-only** — a date is terminal under the Stage rule, so nothing is
    /// staged back into the input. Declares `.date` content: the universal
    /// copy/share long-press, no Edit, exactly a bare value's manners.
    private func dateRow(id: String, title: String, subtitle: String) -> Action {
        Action(
            id: id,
            kind: .calculator,
            title: title,
            subtitle: subtitle,
            inputTypes: [],
            outputType: .date,
            content: .date
        ) { _ in .copyText(title) }
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
    /// The **Copy** row for a detected hex color (CONTEXT.md → Detected result; issue
    /// #217): verb-titled like its Open / Message / Call / Email siblings, subtitled
    /// with the notation the user typed, and **copy-only** — a color is terminal
    /// under the Stage rule, so nothing is staged back into the input, unlike a
    /// Calculator answer. Declares bare `.text` content: the universal copy/share
    /// long-press, no Edit, exactly a value row's manners.
    ///
    /// The one thing that sets it apart visually is `glyphTint` — the parsed swatch,
    /// carried from Core so the App tints the leading glyph without re-parsing the
    /// notation.
    private func colorRow(_ detected: DetectedColor) -> Action {
        Action(
            id: "detect.color",
            kind: .calculator,
            title: "Copy",
            subtitle: detected.display,
            inputTypes: [],
            outputType: .text,
            content: .text,
            glyphTint: detected.rgba
        ) { _ in .copyText(detected.display) }
    }

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
