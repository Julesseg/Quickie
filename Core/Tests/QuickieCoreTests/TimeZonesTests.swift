import Foundation
import Testing
@testable import QuickieCore

// The city/abbreviation time-zone registry behind the Date & time timezone
// family (issue #212; CONTEXT.md → Date & time): the same alias-table shape as
// the unit registry — every accepted spelling keyed to a system time-zone
// identifier, one registry shared across languages. The system supplies the
// offset math; the registry only names zones.
struct TimeZonesTests {

    @Test("a city name resolves to its system time zone")
    func cityResolves() {
        #expect(TimeZones.timeZone(for: "tokyo") == TimeZone(identifier: "Asia/Tokyo"))
        #expect(TimeZones.timeZone(for: "paris") == TimeZone(identifier: "Europe/Paris"))
        #expect(TimeZones.timeZone(for: "new york") == TimeZone(identifier: "America/New_York"))
    }

    @Test("an abbreviation names its region's zone, so DST is the system's call")
    func abbreviationResolves() {
        // "9am PST" in July means 9am Los Angeles time (PDT) — an abbreviation
        // is how people name the region, not a fixed offset.
        #expect(TimeZones.timeZone(for: "pst") == TimeZone(identifier: "America/Los_Angeles"))
        #expect(TimeZones.timeZone(for: "cet") == TimeZone(identifier: "Europe/Paris"))
        #expect(TimeZones.timeZone(for: "jst") == TimeZone(identifier: "Asia/Tokyo"))
    }

    @Test("an unknown name declines with nil")
    func unknownDeclines() {
        #expect(TimeZones.timeZone(for: "gotham") == nil)
        #expect(TimeZones.timeZone(for: "") == nil)
    }

    @Test("every registered identifier resolves to a real system time zone")
    func everyIdentifierResolves() {
        // The registry only names zones — the system supplies the offset math —
        // so a typo'd or too-new identifier must fail loudly here, per platform.
        for (alias, identifier) in TimeZones.registry {
            #expect(TimeZone(identifier: identifier) != nil, "\(alias) → \(identifier) does not resolve")
        }
    }

    @Test("lookup folds case and diacritics, like the unit registry")
    func lookupFoldsCaseAndDiacritics() {
        #expect(TimeZones.timeZone(for: "Zürich") == TimeZone(identifier: "Europe/Zurich"))
        #expect(TimeZones.timeZone(for: "SÃO PAULO") == TimeZone(identifier: "America/Sao_Paulo"))
        #expect(TimeZones.timeZone(for: "Tokio") == TimeZone(identifier: "Asia/Tokyo"))
        #expect(TimeZones.timeZone(for: "nueva york") == TimeZone(identifier: "America/New_York"))
    }
}
