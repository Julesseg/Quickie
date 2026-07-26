import Foundation
import Testing
@testable import QuickieCore

// The Computed provider's **Date & time** rows (issues #210/#212; CONTEXT.md →
// Date & time): a relative-arithmetic query surfaces a boosted *date* row, an
// until/since query a boosted *count* row, a timezone conversion a boosted
// *time* row. The row shapes follow the Stage rule (CONTEXT.md → Stage) —
// staging follows the answer's kind: the date and time answers are terminal,
// so their rows are copy-only with `.date` content, locale-formatted; the
// count answer is a number, so its row has full Calculator manners
// (copy-and-stage, `.number`), indistinguishable from a math result. The
// provider takes an injected clock and calendar, so "today" here is a fixed
// Wednesday. Grammar coverage lives in DateGrammarTests; these tests pin the
// row shapes, the toggle, and non-arbitration.
struct ComputedDateTimeTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Mid-morning on **Wednesday, July 15, 2026** — the same fixed "now" as
    /// DateGrammarTests.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 9, minute: 30))!

    private let provider = ComputedProvider(calendar: calendar, now: { now })

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("a relative-arithmetic query yields one boosted copy-only date row")
    func dateAnswerRowIsCopyOnly() {
        let rows = provider.candidates(for: "3 weeks from friday")
        #expect(rows.count == 1)

        // The title (and copied text) is the locale-formatted date — August 7,
        // 2026 — and the main action *only* copies: a date is terminal, nothing
        // is staged back into the input (CONTEXT.md → Stage).
        let formatted = DateGrammar.formatted(date(2026, 8, 7), calendar: Self.calendar)
        #expect(rows.first?.title == formatted)
        #expect(rows.first?.subtitle == "3 weeks from friday")
        #expect(rows.first?.run() == .copyText(formatted))
    }

    @Test("a date answer declares .date content: universal copy/share, no Edit")
    func dateAnswerContentAndMenu() {
        let row = provider.candidates(for: "2 days ago").first
        #expect(row?.content == .date)
        #expect(row?.outputType == .date)
        #expect(row.map { secondaryActions(for: $0.content) } == [.copy, .share, .copyDeeplink])
    }

    @Test("an until/since query yields a count row with full Calculator manners")
    func countAnswerRowCopiesAndStages() {
        let rows = provider.candidates(for: "days until dec 25")
        #expect(rows.count == 1)

        // A number-valued answer *is* arithmetic whatever question produced it:
        // copy-and-stage, `.number` content — indistinguishable from a math row.
        #expect(rows.first?.title == "163")
        #expect(rows.first?.run() == .copyAndStage(text: "163"))
        #expect(rows.first?.content == .number)
        #expect(rows.first?.outputType == .number)
        #expect(rows.first?.subtitle == "days until dec 25")
    }

    @Test("date rows are boosted-dynamic, never fallback")
    func dateRowsAreBoostedDynamic() {
        #expect(provider.kind == .dynamic)
        #expect(provider.candidates(for: "3 weeks from friday").first?.isFallbackEligible == false)
        #expect(provider.candidates(for: "days until dec 25").first?.isFallbackEligible == false)
    }

    @Test("a timezone conversion yields one boosted copy-only time row")
    func timeAnswerRowIsCopyOnly() {
        let rows = provider.candidates(for: "9am pst in tokyo")
        #expect(rows.count == 1)

        // The title (and copied text) is the converted time, locale-formatted in
        // the target zone with the crossed-midnight marker — 1:00 AM +1 in Tokyo
        // — and, a time being terminal like a date (CONTEXT.md → Stage), the
        // main action *only* copies.
        let formatted = DateGrammar.formattedTime(
            Self.calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 16))!,
            in: TimeZone(identifier: "Asia/Tokyo")!,
            dayOffset: 1,
            calendar: Self.calendar
        )
        #expect(rows.first?.id == "date.timezone")
        #expect(rows.first?.title == formatted)
        #expect(rows.first?.subtitle == "9am pst in tokyo")
        #expect(rows.first?.run() == .copyText(formatted))
        #expect(rows.first?.content == .date)
        #expect(rows.first?.outputType == .date)
    }

    @Test("the row ids name the three families for the UI layer")
    func rowIDsNameTheFamilies() {
        #expect(provider.candidates(for: "tomorrow + 2 weeks").first?.id == "date.relative")
        #expect(provider.candidates(for: "weeks since jan 1").first?.id == "date.count")
        #expect(provider.candidates(for: "3pm in paris").first?.id == "date.timezone")
    }

    @Test("the Date & time toggle off suppresses all three families and nothing else")
    func toggleSuppressesExactlyItsRows() {
        let off = ComputedProvider(dateTime: false, calendar: Self.calendar, now: { Self.now })
        #expect(off.candidates(for: "3 weeks from friday").isEmpty)
        #expect(off.candidates(for: "days until dec 25").isEmpty)
        // The timezone family rides the same toggle — no setting of its own.
        #expect(off.candidates(for: "9am pst in tokyo").isEmpty)
        // Math is untouched — the toggle gates only the date grammar.
        #expect(off.candidates(for: "2+2").first?.id == "calc.math")
    }

    @Test("a date query carrying an operator fires only its date row — no math row")
    func operatorCarryingDateQueryStaysSingleRow() {
        // "tomorrow + 2 weeks" contains "+", so the math branch *tries* — and
        // declines (words don't evaluate). Branches stay non-arbitrating: every
        // applicable interpretation fires, and only the date one applies here.
        let rows = provider.candidates(for: "tomorrow + 2 weeks")
        #expect(rows.map(\.id) == ["date.relative"])
    }

    @Test("date rows parse English regardless of the injected device calendar's locale")
    func englishParsesUnderForeignDeviceLocale() {
        var french = Self.calendar
        french.locale = Locale(identifier: "fr_FR")
        let provider = ComputedProvider(calendar: french, now: { Self.now })

        // The dual-accept floor (ADR 0036): the phrase parses — and the *answer*
        // formats per the device locale, French here.
        let rows = provider.candidates(for: "3 weeks from friday")
        #expect(rows.count == 1)
        #expect(rows.first?.title == DateGrammar.formatted(date(2026, 8, 7), calendar: french))
    }

    @Test("non-date queries add no date rows")
    func declinesCleanly() {
        #expect(provider.candidates(for: "quick brown fox").isEmpty)
        // A bare number stays inert (the bare-number principle) — no date row,
        // no math row.
        #expect(provider.candidates(for: "42").isEmpty)
    }
}
