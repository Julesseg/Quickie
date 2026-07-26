import Foundation

/// A calendar unit a date query counts or offsets in — the "weeks" of
/// "3 weeks from friday" and the "days" of "days until dec 25" (issue #210).
public enum DateUnit: Sendable, Equatable {
    case day
    case week
    case month
    case year

    /// The `Calendar.Component` the unit offsets and counts through, so the
    /// arithmetic is always the injected calendar's — never day-count math.
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// One language's contribution to the date grammar (ADR 0036): the ~15
/// connector/unit/anchor keywords of that language, plus the locale whose
/// **system calendar symbols** supply its weekday and month names — those are
/// never hand-written into a table. The parser skeleton is language-independent;
/// adding a language is a new table plus tests, no parser change.
public struct DateKeywordTable: Sendable, Equatable {
    /// The locale whose localized calendar symbols provide this language's
    /// weekday and month names (e.g. `"en_US"` → "friday", "december").
    public let localeIdentifier: String
    /// Unit words, each mapped to its calendar unit ("day"/"days" → `.day`).
    public let units: [String: DateUnit]
    /// Words meaning the current day ("today", "now").
    public let today: Set<String>
    /// Words meaning the day after today ("tomorrow").
    public let tomorrow: Set<String>
    /// Words meaning the day before today ("yesterday").
    public let yesterday: Set<String>
    /// Forward connectors: `<n> <unit> <forward> <anchor>` ("from", "after").
    public let forward: Set<String>
    /// Postfix backward markers: `<n> <unit> <ago>` ("ago").
    public let ago: Set<String>
    /// Count-forward connectors: `<unit> <until> <date>` ("until", "till").
    public let until: Set<String>
    /// Count-backward connectors: `<unit> <since> <date>` ("since").
    public let since: Set<String>

    public init(
        localeIdentifier: String,
        units: [String: DateUnit],
        today: Set<String>,
        tomorrow: Set<String>,
        yesterday: Set<String>,
        forward: Set<String>,
        ago: Set<String>,
        until: Set<String>,
        since: Set<String>
    ) {
        self.localeIdentifier = localeIdentifier
        self.units = units
        self.today = today
        self.tomorrow = tomorrow
        self.yesterday = yesterday
        self.forward = forward
        self.ago = ago
        self.until = until
        self.since = since
    }

    /// The English table — the **dual-accept floor** (ADR 0036): it is always in
    /// the accepted set regardless of device locale, so every hint, doc, and
    /// screenshot phrase parses for every user and localization work can never
    /// break an English query.
    public static let english = DateKeywordTable(
        localeIdentifier: "en_US",
        units: [
            "day": .day, "days": .day,
            "week": .week, "weeks": .week,
            "month": .month, "months": .month,
            "year": .year, "years": .year,
        ],
        today: ["today", "now"],
        tomorrow: ["tomorrow"],
        yesterday: ["yesterday"],
        forward: ["from", "after"],
        ago: ["ago"],
        until: ["until", "till", "til"],
        since: ["since"]
    )
}

/// A parsed date query's answer, in one of the two kinds the Stage rule keys on
/// (CONTEXT.md → Stage): a **date** (terminal — its row is copy-only) or a
/// **count** (a number — its row gets full Calculator manners). The provider
/// maps the kind to the row shape; the grammar only answers.
public enum DateAnswer: Sendable, Equatable {
    case date(Date)
    case count(Int)
}

/// The **Date & time grammar core** (issue #210; ADR 0036; CONTEXT.md → Date &
/// time): a hand-rolled, language-independent parser skeleton — number + unit
/// word + connector + anchor word — fed by per-language `DateKeywordTable`s.
/// This slice ships two grammar families:
///
/// - **Relative arithmetic** → a date: "3 weeks from friday", "tomorrow + 2
///   weeks", "2 days ago". A bare weekday anchor means the nearest *future*
///   occurrence, today included.
/// - **Until/since counts** → a number: "days until dec 25", "weeks since
///   jan 1". A yearless month-day resolves to the nearest occurrence in the
///   connector's direction (until → future, since → past), today included. A
///   target that is unambiguously on the connector's wrong side ("days until
///   yesterday", an explicit past year) still answers — negatively: once the
///   answer is a number it *is* arithmetic (CONTEXT.md → Stage), and honest
///   arithmetic is never refused.
///
/// Hand-rolled because `NSDataDetector` is excluded from Core (the suite runs
/// under `swift test` on Linux) and third-party parsers are out (ADR 0004).
/// Weekday and month names are never hand-written: each table names a locale
/// and the parser reads that locale's calendar symbols. All date arithmetic
/// flows through the injected calendar; answers are start-of-day dates or
/// whole-unit counts, computed against the injected "now".
public enum DateGrammar {

    /// Parses `query` against every table, returning each distinct answer —
    /// non-arbitrating, like every Computed branch: a phrase valid in two
    /// grammars fires each interpretation, but identical answers dedupe so a
    /// second language never doubles an unambiguous row. Returns `[]` for
    /// anything that is not a date query, which is how the provider declines.
    public static func answers(
        for query: String,
        tables: [DateKeywordTable] = [.english],
        calendar: Calendar,
        now: Date
    ) -> [DateAnswer] {
        let tokens = tokenize(query)
        guard tokens.count >= 3 else { return [] }

        var answers: [DateAnswer] = []
        for table in tables {
            let context = Context(table: table, calendar: calendar, today: calendar.startOfDay(for: now))
            if let answer = parse(tokens, context: context), !answers.contains(answer) {
                answers.append(answer)
            }
        }
        return answers
    }

    /// Formats a date answer for display and copying: the device locale's
    /// **full** date style (weekday visible — usually the point of date
    /// arithmetic), no time. The grammar is dual-accept; the answer is not
    /// (ADR 0036) — output always follows the device.
    public static func formatted(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Parsing

    /// Everything one table's parse needs: the table's keywords, the *device*
    /// calendar all arithmetic runs through, today's start-of-day, and the
    /// weekday/month symbol maps derived from the table's locale.
    private struct Context {
        let table: DateKeywordTable
        let calendar: Calendar
        let today: Date
        let weekdays: [String: Int]
        let months: [String: Int]

        init(table: DateKeywordTable, calendar: Calendar, today: Date) {
            self.table = table
            self.calendar = calendar
            self.today = today

            // The table's language borrows its weekday/month names from the
            // system calendar's localized symbols (ADR 0036) — full and short
            // forms, normalized like query tokens (lowercased, trailing period
            // stripped, so "déc." matches a typed "déc").
            var symbolCalendar = Calendar(identifier: calendar.identifier)
            symbolCalendar.locale = Locale(identifier: table.localeIdentifier)

            var weekdays: [String: Int] = [:]
            for symbols in [symbolCalendar.weekdaySymbols, symbolCalendar.shortWeekdaySymbols] {
                for (index, name) in symbols.enumerated() {
                    weekdays[Self.normalize(name)] = index + 1
                }
            }
            self.weekdays = weekdays

            var months: [String: Int] = [:]
            for symbols in [symbolCalendar.monthSymbols, symbolCalendar.shortMonthSymbols] {
                for (index, name) in symbols.enumerated() {
                    months[Self.normalize(name)] = index + 1
                }
            }
            self.months = months
        }

        static func normalize(_ symbol: String) -> String {
            var name = symbol.lowercased()
            if name.hasSuffix(".") { name.removeLast() }
            return name
        }
    }

    /// Lowercases and splits the query, padding `+`/`-` into standalone operator
    /// tokens and shedding the punctuation a typed question carries (commas,
    /// a trailing "?"), so "Days until Dec 25, 2027?" tokenizes cleanly.
    private static func tokenize(_ query: String) -> [String] {
        var text = query.lowercased()
        text = text.replacingOccurrences(of: ",", with: " ")
        text = text.replacingOccurrences(of: "?", with: " ")
        text = text.replacingOccurrences(of: "+", with: " + ")
        text = text.replacingOccurrences(of: "-", with: " - ")
        return text.split(whereSeparator: { $0.isWhitespace }).map { Context.normalize(String($0)) }
    }

    /// One table's parse: tries each family's shape in turn and returns the
    /// first answer. The shapes are structurally disjoint (a count query leads
    /// with a unit word, arithmetic with a number or an anchor), so within one
    /// table a query has at most one reading.
    private static func parse(_ tokens: [String], context: Context) -> DateAnswer? {
        // <n> <unit> <forward> <anchor…> — "3 weeks from friday"
        if tokens.count >= 4,
           let n = number(tokens[0]),
           let unit = context.table.units[tokens[1]],
           context.table.forward.contains(tokens[2]),
           let anchor = resolveDate(Array(tokens[3...]), direction: .future, context: context),
           let result = context.calendar.date(byAdding: unit.component, value: n, to: anchor) {
            return .date(result)
        }

        // <n> <unit> <ago> — "2 days ago"
        if tokens.count == 3,
           let n = number(tokens[0]),
           let unit = context.table.units[tokens[1]],
           context.table.ago.contains(tokens[2]),
           let result = context.calendar.date(byAdding: unit.component, value: -n, to: context.today) {
            return .date(result)
        }

        // <anchor…> ± <n> <unit> — "tomorrow + 2 weeks"
        if tokens.count >= 4 {
            let op = tokens[tokens.count - 3]
            if op == "+" || op == "-",
               let n = number(tokens[tokens.count - 2]),
               let unit = context.table.units[tokens[tokens.count - 1]],
               let anchor = resolveDate(Array(tokens[..<(tokens.count - 3)]), direction: .future, context: context),
               let result = context.calendar.date(byAdding: unit.component, value: op == "+" ? n : -n, to: anchor) {
                return .date(result)
            }
        }

        // <unit> <until|since> <date…> — "days until dec 25", "weeks since jan 1"
        if tokens.count >= 3, let unit = context.table.units[tokens[0]] {
            let rest = Array(tokens[2...])
            if context.table.until.contains(tokens[1]),
               let target = resolveDate(rest, direction: .future, context: context),
               let count = count(from: context.today, to: target, unit: unit, calendar: context.calendar) {
                return .count(count)
            }
            if context.table.since.contains(tokens[1]),
               let target = resolveDate(rest, direction: .past, context: context),
               let count = count(from: target, to: context.today, unit: unit, calendar: context.calendar) {
                return .count(count)
            }
        }

        return nil
    }

    // MARK: - Date expressions

    /// Which way a yearless anchor resolves: "until"/forward anchors pick the
    /// nearest *future* occurrence, "since" the nearest *past* — today included
    /// on both sides, so "friday" on a Friday is today.
    private enum Direction {
        case future
        case past
    }

    /// Resolves an anchor/date expression to a start-of-day date: an anchor
    /// word (today/tomorrow/yesterday), a weekday name, a month-day in either
    /// order ("dec 25", "25 dec"), or a month-day with an explicit year.
    private static func resolveDate(_ tokens: [String], direction: Direction, context: Context) -> Date? {
        switch tokens.count {
        case 1:
            let word = tokens[0]
            if context.table.today.contains(word) { return context.today }
            if context.table.tomorrow.contains(word) {
                return context.calendar.date(byAdding: .day, value: 1, to: context.today)
            }
            if context.table.yesterday.contains(word) {
                return context.calendar.date(byAdding: .day, value: -1, to: context.today)
            }
            if let weekday = context.weekdays[word] {
                return nearestWeekday(weekday, direction: direction, context: context)
            }
            return nil
        case 2:
            guard let (month, day) = monthDay(tokens[0], tokens[1], context: context) else { return nil }
            return nearestMonthDay(month: month, day: day, direction: direction, context: context)
        case 3:
            guard let (month, day) = monthDay(tokens[0], tokens[1], context: context),
                  let year = yearNumber(tokens[2]) else { return nil }
            return exactDate(year: year, month: month, day: day, calendar: context.calendar)
        default:
            return nil
        }
    }

    /// Reads a month-day pair in either order — "dec 25" or "25 dec" — against
    /// the table's month symbols.
    private static func monthDay(_ first: String, _ second: String, context: Context) -> (month: Int, day: Int)? {
        if let month = context.months[first], let day = dayNumber(second) { return (month, day) }
        if let day = dayNumber(first), let month = context.months[second] { return (month, day) }
        return nil
    }

    /// The nearest occurrence of `weekday` in `direction`, today included.
    private static func nearestWeekday(_ weekday: Int, direction: Direction, context: Context) -> Date? {
        let current = context.calendar.component(.weekday, from: context.today)
        let delta: Int
        switch direction {
        case .future: delta = (weekday - current + 7) % 7
        case .past: delta = -((current - weekday + 7) % 7)
        }
        return context.calendar.date(byAdding: .day, value: delta, to: context.today)
    }

    /// The nearest valid occurrence of a yearless month-day in `direction`,
    /// today included. Scans a handful of years so February 29 resolves to the
    /// next (or last) leap year instead of failing or rolling over.
    private static func nearestMonthDay(month: Int, day: Int, direction: Direction, context: Context) -> Date? {
        let thisYear = context.calendar.component(.year, from: context.today)
        let step = direction == .future ? 1 : -1
        for offset in 0...8 {
            guard let candidate = exactDate(year: thisYear + offset * step, month: month, day: day, calendar: context.calendar) else { continue }
            switch direction {
            case .future: if candidate >= context.today { return candidate }
            case .past: if candidate <= context.today { return candidate }
            }
        }
        return nil
    }

    /// A validated year-month-day as a start-of-day date. The round-trip check
    /// rejects impossible dates ("feb 30") instead of letting the calendar roll
    /// them over — a rolled-over answer would be a guess, and Computed never
    /// guesses.
    private static func exactDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    // MARK: - Numbers and counts

    /// Whole calendar units from `from` to `to` — the calendar's own difference
    /// (truncating), so "weeks since jan 1" means whole elapsed weeks.
    private static func count(from: Date, to: Date, unit: DateUnit, calendar: Calendar) -> Int? {
        calendar.dateComponents([unit.component], from: from, to: to).value(for: unit.component)
    }

    /// A plain digit run as an offset count, bounded so absurd input can't ask
    /// the calendar for pathological arithmetic.
    private static func number(_ token: String) -> Int? {
        guard !token.isEmpty, token.count <= 5, token.allSatisfy(\.isNumber), let value = Int(token) else { return nil }
        return value
    }

    /// A day-of-month digit run (1–31; exact validity is the calendar's call).
    private static func dayNumber(_ token: String) -> Int? {
        guard let value = number(token), (1...31).contains(value) else { return nil }
        return value
    }

    /// A four-digit explicit year.
    private static func yearNumber(_ token: String) -> Int? {
        guard token.count == 4, let value = number(token) else { return nil }
        return value
    }
}
