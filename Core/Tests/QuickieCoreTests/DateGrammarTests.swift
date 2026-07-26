import Foundation
import Testing
@testable import QuickieCore

// The Date & time grammar core (issues #210/#211/#212; ADR 0036; CONTEXT.md →
// Date & time): a language-independent parser skeleton — number + unit word +
// connector + anchor word — fed by per-language keyword tables: English plus
// the French, Spanish, and German launch tables. These tests pin the three
// families (relative arithmetic → a date, until/since → a count, timezone
// conversion → a time), the anchor semantics (a bare weekday is the nearest
// future occurrence, today included), the dual-accept floor (English parses
// regardless of device locale), the data-only extension path (a toy table
// parses with zero parser changes), and the launch tables' coverage and
// selection. Everything runs against an injected calendar and clock, so
// "today" is a fixed Wednesday.
struct DateGrammarTests {

    /// A fixed device calendar: Gregorian, en_US, UTC — every expectation below
    /// is computed against it, never against the machine's real locale.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// "Now" is mid-morning on **Wednesday, July 15, 2026** — a weekday chosen so
    /// nearest-future and nearest-past weekday resolution are both non-trivial.
    private var now: Date { date(2026, 7, 15, hour: 9, minute: 30) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func answers(_ query: String, tables: [DateKeywordTable] = [.english], calendar: Calendar? = nil) -> [DateAnswer] {
        DateGrammar.answers(for: query, tables: tables, calendar: calendar ?? self.calendar, now: now)
    }

    // MARK: - Relative arithmetic → a date

    @Test("'3 weeks from friday' lands three weeks after the nearest future friday")
    func weeksFromWeekday() {
        // Friday nearest Wednesday July 15 (future, today included) is July 17;
        // three weeks on is August 7.
        #expect(answers("3 weeks from friday") == [.date(date(2026, 8, 7))])
    }

    @Test("'tomorrow + 2 weeks' adds onto the tomorrow anchor")
    func anchorPlusOffset() {
        #expect(answers("tomorrow + 2 weeks") == [.date(date(2026, 7, 30))])
    }

    @Test("'2 days ago' counts back from today")
    func daysAgo() {
        #expect(answers("2 days ago") == [.date(date(2026, 7, 13))])
    }

    @Test("a minus operator subtracts from the anchor")
    func anchorMinusOffset() {
        #expect(answers("today - 3 days") == [.date(date(2026, 7, 12))])
    }

    @Test("a bare weekday anchor means the nearest future occurrence, today included")
    func bareWeekdayAnchorIncludesToday() {
        // "wednesday" on a Wednesday is *today*, not next week (issue #210 AC #1).
        #expect(answers("1 week from wednesday") == [.date(date(2026, 7, 22))])
    }

    @Test("'after' works as a forward connector and month-day works as an anchor")
    func afterConnectorAndMonthDayAnchor() {
        #expect(answers("2 days after dec 25") == [.date(date(2026, 12, 27))])
    }

    @Test("a date answer is normalized to the start of its day")
    func dateAnswersAreStartOfDay() {
        // "now" carries 09:30; the answer must not.
        guard case .date(let result)? = answers("2 days ago").first else {
            Issue.record("expected a date answer")
            return
        }
        #expect(result == calendar.startOfDay(for: result))
    }

    // MARK: - Until/since → a count

    @Test("'days until dec 25' counts forward to the nearest future occurrence")
    func daysUntil() {
        // July 15 → December 25, 2026 is 163 days.
        #expect(answers("days until dec 25") == [.count(163)])
    }

    @Test("'weeks since jan 1' counts whole weeks back to the nearest past occurrence")
    func weeksSince() {
        // January 1 → July 15, 2026 is 195 days: 27 whole weeks.
        #expect(answers("weeks since jan 1") == [.count(27)])
    }

    @Test("'days until friday' counts to the nearest future weekday")
    func daysUntilWeekday() {
        #expect(answers("days until friday") == [.count(2)])
    }

    @Test("'days since monday' counts from the nearest past weekday")
    func daysSinceWeekday() {
        #expect(answers("days since monday") == [.count(2)])
    }

    @Test("an explicit year pins the target instead of resolving to the nearest occurrence")
    func untilWithExplicitYear() {
        // 163 days to December 25, 2026, plus the 365 days of non-leap 2027.
        #expect(answers("days until dec 25 2027") == [.count(528)])
    }

    @Test("a yearless month-day already past resolves forward across the year boundary")
    func untilCrossesYearBoundary() {
        // January 1 has passed in 2026, so "until" means January 1, 2027.
        #expect(answers("days until jan 1") == [.count(170)])
    }

    @Test("day-month order parses like month-day, and long month names work")
    func dayMonthOrderAndLongNames() {
        #expect(answers("days until 25 dec") == [.count(163)])
        #expect(answers("days until december 25") == [.count(163)])
    }

    @Test("a target on the connector's wrong side answers a negative count, honestly")
    func wrongSideTargetsCountNegative() {
        // "until" something already past is answered, not declined: once the
        // answer is a number it *is* arithmetic (CONTEXT.md → Stage), and the
        // Calculator never refuses honest arithmetic. Direction only steers
        // *yearless* resolution — an absolute target says what it says.
        #expect(answers("days until yesterday") == [.count(-1)])
        #expect(answers("days since tomorrow") == [.count(-1)])
        #expect(answers("days until dec 25 2025") == [.count(-202)])
    }

    @Test("months count in whole calendar months")
    func monthsUntil() {
        // July 15 → December 25 is five whole months and change.
        #expect(answers("months until dec 25") == [.count(5)])
    }

    @Test("the grammar is case-insensitive")
    func caseInsensitive() {
        #expect(answers("Days Until Dec 25") == [.count(163)])
        #expect(answers("3 Weeks From Friday") == [.date(date(2026, 8, 7))])
    }

    // MARK: - Declining

    @Test("non-date queries decline cleanly", arguments: [
        "42",              // a bare number stays inert
        "friday",          // a bare weekday alone is prose, not a question
        "2 days",          // an offset with no connector or anchor
        "days until",      // a question with no target
        "days until feb 30", // an impossible date never resolves by rollover
        "days until 32 dec", // an impossible day number
        "until dec 25",    // no unit word — nothing to count
        "3 parsecs from friday", // an unknown unit word
        "",
    ])
    func declines(_ query: String) {
        #expect(answers(query) == [])
    }

    // MARK: - Dual accept (ADR 0036)

    @Test("English parses regardless of the device locale")
    func englishParsesUnderForeignLocale() {
        // The device calendar speaks French; the English table still supplies the
        // English keywords and weekday symbols (the dual-accept floor, ADR 0036).
        var french = calendar
        french.locale = Locale(identifier: "fr_FR")
        #expect(answers("3 weeks from friday", calendar: french) == [.date(date(2026, 8, 7))])
        #expect(answers("days until dec 25", calendar: french) == [.count(163)])
    }

    // MARK: - Table architecture (data-only extension)

    /// A toy language whose ~15 keywords are invented, riding on real French
    /// calendar symbols — proof a new language is a table, not a parser change.
    private var toyTable: DateKeywordTable {
        DateKeywordTable(
            localeIdentifier: "fr_FR",
            units: ["zorp": .day, "blib": .week],
            today: ["nunc"],
            tomorrow: ["cras"],
            yesterday: ["heri"],
            forward: ["vers"],
            ago: ["retro"],
            until: ["jusqua"],
            since: ["depuis"]
        )
    }

    @Test("a toy keyword table parses with zero parser changes")
    func toyTableParses() {
        #expect(answers("3 zorp vers cras", tables: [toyTable]) == [.date(date(2026, 7, 19))])
        #expect(answers("2 zorp retro", tables: [toyTable]) == [.date(date(2026, 7, 13))])
    }

    @Test("a table's weekday and month names come from the system calendar's localized symbols")
    func toyTableUsesLocalizedCalendarSymbols() {
        // "vendredi" (Friday) and "déc" (December) are never written in the table —
        // they come from the fr_FR calendar symbols the table's locale names.
        #expect(answers("1 blib vers vendredi", tables: [toyTable]) == [.date(date(2026, 7, 24))])
        #expect(answers("zorp jusqua déc 25", tables: [toyTable]) == [.count(163)])
    }

    @Test("a phrase valid in two accepted grammars fires each interpretation")
    func distinctAnswersAcrossTablesBothFire() {
        // A crafted second table reads "days" as *weeks*, so "2 days from
        // today" is valid in both grammars with different answers. Both fire,
        // in table order — non-arbitrating, per the standing Computed rule
        // (ADR 0036): the user picks, the grammar never does.
        let contrarian = DateKeywordTable(
            localeIdentifier: "en_US",
            units: ["days": .week],
            today: ["today"], tomorrow: [], yesterday: [],
            forward: ["from"], ago: [], until: [], since: []
        )
        #expect(answers("2 days from today", tables: [.english, contrarian])
            == [.date(date(2026, 7, 17)), .date(date(2026, 7, 29))])
    }

    @Test("two tables yielding the same answer collapse to one row's worth")
    func identicalAnswersAcrossTablesDedupe() {
        // Both tables resolve "2 days ago"-shaped queries; identical answers dedupe
        // so a future second language never doubles an unambiguous row.
        let englishy = DateKeywordTable(
            localeIdentifier: "en_US",
            units: ["days": .day],
            today: [], tomorrow: [], yesterday: [],
            forward: [], ago: ["ago"], until: [], since: []
        )
        #expect(answers("2 days ago", tables: [.english, englishy]) == [.date(date(2026, 7, 13))])
    }

    // MARK: - Launch tables (issue #211, ADR 0036)

    @Test("French: 'à partir de' connects forward arithmetic, weekday names from fr symbols")
    func frenchForwardArithmetic() {
        // The issue's worked example: nearest future Friday is July 17, three
        // weeks on is August 7 — same answer as "3 weeks from friday".
        #expect(answers("3 semaines à partir de vendredi", tables: [.english, .french]) == [.date(date(2026, 8, 7))])
    }

    @Test("French: 'jours jusqu'à noël' counts to the named day")
    func frenchDaysUntilChristmas() {
        #expect(answers("jours jusqu'à noël", tables: [.english, .french]) == [.count(163)])
        // The apostrophe-and-article contraction and a month-day target too.
        #expect(answers("jours jusqu'au 25 déc", tables: [.english, .french]) == [.count(163)])
    }

    @Test("French phrases parse without accents, apostrophes, or with iOS curly quotes")
    func frenchTypingVariants() {
        // Diacritic-free and apostrophe-free typing is normal on many keyboards;
        // iOS smart punctuation types U+2019 — all fold to the same keywords.
        #expect(answers("3 semaines a partir de vendredi", tables: [.english, .french]) == [.date(date(2026, 8, 7))])
        #expect(answers("jours jusqua noel", tables: [.english, .french]) == [.count(163)])
        #expect(answers("jours jusqu\u{2019}à noël", tables: [.english, .french]) == [.count(163)])
    }

    @Test("French: 'il y a' leads a relative-past phrase and 'demain' anchors")
    func frenchPastAndAnchors() {
        #expect(answers("il y a 2 jours", tables: [.english, .french]) == [.date(date(2026, 7, 13))])
        #expect(answers("demain + 2 semaines", tables: [.english, .french]) == [.date(date(2026, 7, 30))])
    }

    @Test("Spanish: forward arithmetic, until counts, and 'hace' relative past")
    func spanishCoverage() {
        #expect(answers("3 semanas a partir del viernes", tables: [.english, .spanish]) == [.date(date(2026, 8, 7))])
        #expect(answers("días hasta navidad", tables: [.english, .spanish]) == [.count(163)])
        #expect(answers("semanas desde el 1 ene", tables: [.english, .spanish]) == [.count(27)])
        #expect(answers("hace 2 días", tables: [.english, .spanish]) == [.date(date(2026, 7, 13))])
    }

    @Test("German: forward arithmetic, until counts, and 'vor' relative past")
    func germanCoverage() {
        #expect(answers("3 wochen ab freitag", tables: [.english, .german]) == [.date(date(2026, 8, 7))])
        #expect(answers("tage bis weihnachten", tables: [.english, .german]) == [.count(163)])
        #expect(answers("tage bis zum 25 dez", tables: [.english, .german]) == [.count(163)])
        #expect(answers("vor 2 tagen", tables: [.english, .german]) == [.date(date(2026, 7, 13))])
    }

    @Test("English gains the same named-day anchor: 'days until christmas'")
    func englishNamedDay() {
        #expect(answers("days until christmas") == [.count(163)])
        #expect(answers("days until xmas") == [.count(163)])
    }

    @Test("dual accept: English parses unchanged with a language table layered on")
    func englishParsesWithLayeredTable() {
        // The floor (ADR 0036): every English phrase keeps its single answer —
        // the layered table never doubles or shifts it.
        #expect(answers("3 weeks from friday", tables: [.english, .french]) == [.date(date(2026, 8, 7))])
        #expect(answers("days until dec 25", tables: [.english, .german]) == [.count(163)])
    }

    @Test("only the device language's table layers on English, never all four")
    func tableSelectionFollowsDeviceLanguage() {
        #expect(DateKeywordTable.tables(for: Locale(identifier: "fr_CA")) == [.english, .french])
        #expect(DateKeywordTable.tables(for: Locale(identifier: "es_MX")) == [.english, .spanish])
        #expect(DateKeywordTable.tables(for: Locale(identifier: "de_AT")) == [.english, .german])
        #expect(DateKeywordTable.tables(for: Locale(identifier: "en_US")) == [.english])
        #expect(DateKeywordTable.tables(for: Locale(identifier: "it_IT")) == [.english])
    }

    @Test("a French phrase does not parse on a Spanish device — layers don't stack")
    func foreignLanguagePhraseDeclinesOnOtherDevice() {
        #expect(answers("jours jusqu'à noël", tables: DateKeywordTable.tables(for: Locale(identifier: "es_ES"))) == [])
    }

    // MARK: - Timezone conversion (issue #212)

    private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }

    @Test("'9am pst in tokyo' converts a sourced wall-clock time to the target zone")
    func timeWithSourceZone() {
        // 9am Los Angeles (PDT, UTC−7) on July 15 is 16:00 UTC — 1am July 16 in
        // Tokyo, so the answer carries the crossed-midnight day offset.
        #expect(answers("9am pst in tokyo")
            == [.time(date(2026, 7, 15, hour: 16), zone: zone("Asia/Tokyo"), dayOffset: 1)])
    }

    @Test("a sourceless time reads in the device zone: '3pm in paris'")
    func timeWithoutSourceZone() {
        // The device calendar is UTC, so 3pm is 15:00 UTC — 5pm the same day in
        // Paris (CEST, UTC+2).
        #expect(answers("3pm in paris")
            == [.time(date(2026, 7, 15, hour: 15), zone: zone("Europe/Paris"), dayOffset: 0)])
    }

    @Test("a 24-hour clock parses: '15:30 cet in new york'")
    func twentyFourHourClock() {
        // 15:30 Paris (CEST, UTC+2) is 13:30 UTC — 9:30am the same day in New
        // York (EDT, UTC−4).
        #expect(answers("15:30 cet in new york")
            == [.time(date(2026, 7, 15, hour: 13, minute: 30), zone: zone("America/New_York"), dayOffset: 0)])
    }

    @Test("a conversion crossing midnight backward carries a −1 day offset")
    func backwardDayCrossing() {
        // 1am Tokyo on (Tokyo's) July 15 is 16:00 UTC July 14 — 9am July 14 in
        // Los Angeles, the day before.
        #expect(answers("1am jst in la")
            == [.time(date(2026, 7, 14, hour: 16), zone: zone("America/Los_Angeles"), dayOffset: -1)])
    }

    @Test("multi-word zone names work on both sides: '9am new york in hong kong'")
    func multiWordZones() {
        // 9am New York (EDT, UTC−4) is 13:00 UTC — 9pm the same day in Hong Kong.
        #expect(answers("9am new york in hong kong")
            == [.time(date(2026, 7, 15, hour: 13), zone: zone("Asia/Hong_Kong"), dayOffset: 0)])
    }

    @Test("the meridiem may be its own token, and minutes ride with it")
    func detachedMeridiem() {
        #expect(answers("9 am pst in tokyo") == answers("9am pst in tokyo"))
        #expect(answers("9:30 pm in london")
            == [.time(date(2026, 7, 15, hour: 21, minute: 30), zone: zone("Europe/London"), dayOffset: 0)])
    }

    @Test("12am is midnight and 12pm is noon")
    func meridiemTwelves() {
        #expect(answers("12am in tokyo")
            == [.time(date(2026, 7, 15, hour: 0), zone: zone("Asia/Tokyo"), dayOffset: 0)])
        #expect(answers("12pm in tokyo")
            == [.time(date(2026, 7, 15, hour: 12), zone: zone("Asia/Tokyo"), dayOffset: 0)])
    }

    @Test("non-time and non-zone queries decline the timezone family", arguments: [
        "9 in tokyo",        // a bare digit run is not a time (the bare-number principle)
        "13pm in tokyo",     // an impossible 12-hour hour
        "25:00 in tokyo",    // an impossible 24-hour hour
        "9:75 in tokyo",     // an impossible minute
        "9am in gotham",     // an unregistered target
        "9am atlantis in tokyo", // an unregistered source
        "9am pst in",        // a connector with no target
    ])
    func timezoneDeclines(_ query: String) {
        #expect(answers(query) == [])
    }

    @Test("the connector is table data: French 'à' converts, folded or not")
    func frenchTimeZoneConnector() {
        let expected: [DateAnswer] = [.time(date(2026, 7, 15, hour: 15, minute: 30), zone: zone("Asia/Tokyo"), dayOffset: 1)]
        #expect(answers("15:30 à tokyo", tables: [.english, .french]) == expected)
        #expect(answers("15:30 a tokyo", tables: [.english, .french]) == expected)
        // And it is *only* table data — no French table, no French connector.
        #expect(answers("15:30 à tokyo") == [])
    }

    @Test("two tables sharing a connector still yield one answer")
    func timeZoneAnswersDedupeAcrossTables() {
        // English and German both connect with "in"; identical answers collapse.
        #expect(answers("9am pst in tokyo", tables: [.english, .german])
            == [.time(date(2026, 7, 15, hour: 16), zone: zone("Asia/Tokyo"), dayOffset: 1)])
    }

    @Test("a converted time formats per the device locale, in the target zone, with a day marker")
    func formattedTimeFollowsDeviceLocale() {
        // "9am PST in tokyo" renders as Tokyo's 1:00 AM under en_US — and the
        // crossed midnight is flagged with the language-neutral " +1".
        let instant = date(2026, 7, 15, hour: 16)
        let english = DateGrammar.formattedTime(instant, in: zone("Asia/Tokyo"), dayOffset: 1, calendar: calendar)
        #expect(english.contains("1:00"))
        #expect(english.hasSuffix(" +1"))

        var frenchCalendar = calendar
        frenchCalendar.locale = Locale(identifier: "fr_FR")
        let french = DateGrammar.formattedTime(instant, in: zone("Asia/Tokyo"), dayOffset: 1, calendar: frenchCalendar)
        #expect(french != english)

        // No crossing, no marker.
        let plain = DateGrammar.formattedTime(date(2026, 7, 15, hour: 13), in: zone("Asia/Hong_Kong"), dayOffset: 0, calendar: calendar)
        #expect(plain.contains("9:00"))
        #expect(!plain.contains("+"))
    }

    // MARK: - Output formatting

    @Test("a date answer formats per the device locale and calendar")
    func formattedFollowsDeviceLocale() {
        // The grammar is dual-accept; the *answer* is not (ADR 0036): the same
        // date renders as English prose under en_US and French under fr_FR.
        let target = date(2026, 8, 7)
        var frenchCalendar = calendar
        frenchCalendar.locale = Locale(identifier: "fr_FR")

        let english = DateGrammar.formatted(target, calendar: calendar)
        let french = DateGrammar.formatted(target, calendar: frenchCalendar)
        #expect(english.contains("August") && english.contains("2026"))
        #expect(french.contains("août"))
        #expect(english != french)
    }
}
