import Foundation
import Testing
@testable import QuickieCore

// The Detected result half of the Computed provider (CONTEXT.md → Detected
// result; ADR 0032): a whole-query URL / phone number / email surfaces boosted
// rows that act on it — Open, Message + Call, Email. These tests pin the rows
// each type produces, their order and manners (boosted, non-fallback,
// copy/share-no-Edit), the no-arbitration behavior on an ambiguous query, and
// that each per-type toggle suppresses exactly its rows.
struct ComputedDetectionTests {

    private let provider = ComputedProvider()

    // MARK: URL → one Open row

    @Test("a URL yields one Open row that opens the URL")
    func urlYieldsOneOpenRow() {
        let rows = provider.candidates(for: "apple.com")
        #expect(rows.count == 1)
        let open = rows.first
        #expect(open?.id == "detect.url")
        #expect(open?.title == "Open")
        #expect(open?.run() == .openURL(URL(string: "https://apple.com")!))
    }

    // MARK: Email → one Email row

    @Test("an email yields one Email row that opens a mailto compose")
    func emailYieldsOneEmailRow() {
        let rows = provider.candidates(for: "me@work.com")
        #expect(rows.count == 1)
        let email = rows.first
        #expect(email?.id == "detect.email")
        #expect(email?.title == "Email")
        #expect(email?.run() == .openURL(URL(string: "mailto:me@work.com")!))
    }

    // MARK: Phone → two rows, Message nearest the thumb

    @Test("a phone number yields Message then Call, Message the highlighted result")
    func phoneYieldsMessageThenCall() {
        // A phone-only query (a leading `+` is a sign, not an operator, so this is no
        // math expression) — the ambiguous phone-and-math case is exercised below.
        let rows = provider.candidates(for: "+1 555 123 4567")
        #expect(rows.count == 2)
        // results[0] is nearest the input/thumb — a mis-Enter should text, not call.
        #expect(rows.first?.id == "detect.phone.message")
        #expect(rows.first?.title == "Message")
        #expect(rows.first?.run() == .openURL(URL(string: "sms:+15551234567")!))
        // Call rides above it.
        #expect(rows.last?.id == "detect.phone.call")
        #expect(rows.last?.title == "Call")
        #expect(rows.last?.run() == .openURL(URL(string: "tel:+15551234567")!))
    }

    // MARK: Boosted-tier manners

    @Test("detected rows are boosted, non-fallback, and carry a bare copy/share value")
    func detectedRowsShareCalculatorManners() {
        // Dynamic (boosted) + non-fallback is what the SearchEngine floats to the top.
        #expect(provider.kind == .dynamic)
        for query in ["apple.com", "me@work.com", "555-1212"] {
            for row in provider.candidates(for: query) {
                #expect(row.kind == .calculator)
                #expect(row.isFallbackEligible == false)
                // A bare value: the universal copy/share, plus the id-keyed Copy action
                // deeplink every row earns (issue #120) — never Edit.
                #expect(secondaryActions(for: row.content) == [.copy, .share, .copyDeeplink])
            }
        }
    }

    @Test("a phone/email row's copy value resolves to the bare number/address, not the scheme URL")
    func detectedRowCopiesBareValue() {
        // The row opens a `tel:`/`sms:`/`mailto:` URL, but its bare value — what the
        // copy/share menu acts on (CONTEXT.md → Detected result) — is the number or
        // address the user typed, recovered by `bareValue(forDetectedURL:)`.
        let message = provider.candidates(for: "+1 555 123 4567").first { $0.id == "detect.phone.message" }
        if case .openURL(let url)? = message?.run() {
            #expect(TypedContentDetector.bareValue(forDetectedURL: url) == "+15551234567")
        } else {
            Issue.record("the Message row should open an sms: URL")
        }

        let email = provider.candidates(for: "me@work.com").first
        if case .openURL(let url)? = email?.run() {
            #expect(TypedContentDetector.bareValue(forDetectedURL: url) == "me@work.com")
        } else {
            Issue.record("the Email row should open a mailto: URL")
        }

        // The Open row's value is the web URL itself — nothing to strip.
        let open = provider.candidates(for: "apple.com").first
        if case .openURL(let url)? = open?.run() {
            #expect(TypedContentDetector.bareValue(forDetectedURL: url) == nil)
            #expect(url.absoluteString == "https://apple.com")
        } else {
            Issue.record("the Open row should open an https: URL")
        }
    }

    @Test("the Open row's Enter reads as a link, running it opens the URL")
    func openRowEntersAsLink() {
        let open = provider.candidates(for: "apple.com").first
        #expect(open?.returnKeyLabel == .go)
        #expect(open?.mainAction == .openInBrowser)
    }

    // MARK: No arbitration on an ambiguous query

    @Test("an ambiguous query fires rows from every interpretation — no arbitration")
    func ambiguousQueryFiresEveryInterpretation() {
        // `555-1212` reads as a phone number *and* as math (`555 - 1212 = -657`):
        // both fire, separate rows, the user picks (CONTEXT.md → Detected result).
        let ids = provider.candidates(for: "555-1212").map(\.id)
        #expect(ids.contains("detect.phone.message"))
        #expect(ids.contains("detect.phone.call"))
        #expect(ids.contains("calc.math"))
    }

    // MARK: Per-type toggles suppress exactly their rows

    @Test("each detection toggle suppresses exactly its rows")
    func eachToggleSuppressesItsRows() {
        #expect(ComputedProvider(url: false).candidates(for: "apple.com").isEmpty)
        #expect(ComputedProvider(email: false).candidates(for: "me@work.com").isEmpty)
        #expect(ComputedProvider(phone: false).candidates(for: "555-1212").map(\.id) == ["calc.math"])
        // The math toggle off drops the math row but leaves detection intact.
        let phoneOnly = ComputedProvider(math: false).candidates(for: "555-1212").map(\.id)
        #expect(phoneOnly == ["detect.phone.message", "detect.phone.call"])
    }

    @Test("all three detection toggles off restores the pre-detection Calculator")
    func detectionOffRestoresPreDetectionCalculator() {
        // With URLs, Phone numbers, and Email addresses off, only Math and Unit
        // conversion answer — exactly the pre-detection Calculator (ADR 0032).
        let calc = ComputedProvider(url: false, phone: false, email: false)
        #expect(calc.candidates(for: "apple.com").isEmpty)
        #expect(calc.candidates(for: "me@work.com").isEmpty)
        // A phone-shaped math expression still answers math only, as it did before.
        #expect(calc.candidates(for: "555-1212").map(\.id) == ["calc.math"])
        // Math and conversion are untouched.
        #expect(calc.candidates(for: "23*7").first?.title == "161")
        #expect(calc.candidates(for: "20 mi to km").first?.id == "calc.conversion")
    }

    @Test("a plain word or prose still declines cleanly — no detected rows")
    func plainProseDeclines() {
        #expect(provider.candidates(for: "github").isEmpty)
        #expect(provider.candidates(for: "go to apple.com").isEmpty)
        #expect(provider.candidates(for: "call me at 555-1212").isEmpty)
    }
}
