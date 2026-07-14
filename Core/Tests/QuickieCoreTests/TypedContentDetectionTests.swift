import Foundation
import Testing
@testable import QuickieCore

// The pure detector behind the Computed provider's Detected result rows
// (CONTEXT.md → Detected result; ADR 0032): it fires only when the *whole
// trimmed query* parses as exactly one URL / phone number / email address, a
// single trailing punctuation mark tolerated, and never on a substring of longer
// prose. These tests pin that boundary — what fires, what declines, and the
// exact schemed URLs the rows open.
struct TypedContentDetectionTests {

    // MARK: URL

    @Test("a bare domain is a URL, normalized to https")
    func bareDomainIsURL() {
        #expect(TypedContentDetector.url(in: "apple.com")?.absoluteString == "https://apple.com")
        #expect(TypedContentDetector.url(in: "www.apple.com/deals")?.absoluteString == "https://www.apple.com/deals")
    }

    @Test("a schemed URL is used verbatim")
    func schemedURLVerbatim() {
        #expect(TypedContentDetector.url(in: "https://example.org/x?y=1")?.absoluteString == "https://example.org/x?y=1")
        #expect(TypedContentDetector.url(in: "http://example.org")?.absoluteString == "http://example.org")
    }

    @Test("a single trailing punctuation mark is tolerated on a URL")
    func urlToleratesOneTrailingPunctuation() {
        #expect(TypedContentDetector.url(in: "apple.com.")?.absoluteString == "https://apple.com")
        #expect(TypedContentDetector.url(in: "apple.com,")?.absoluteString == "https://apple.com")
    }

    @Test("prose containing a domain never fires as a URL")
    func proseWithDomainDeclines() {
        #expect(TypedContentDetector.url(in: "go to apple.com") == nil)
        #expect(TypedContentDetector.url(in: "apple.com is great") == nil)
    }

    @Test("an all-numeric dotted run is not a URL")
    func numericDottedRunIsNotURL() {
        // `3.14` is a number; its final label is not an alphabetic TLD.
        #expect(TypedContentDetector.url(in: "3.14") == nil)
        #expect(TypedContentDetector.url(in: "192.168.0.1") == nil)
    }

    @Test("a single word with no dot is not a URL")
    func bareWordIsNotURL() {
        #expect(TypedContentDetector.url(in: "github") == nil)
        #expect(TypedContentDetector.url(in: "localhost") == nil)
    }

    @Test("an email address is not detected as a URL")
    func emailIsNotURL() {
        // The `@` routes to the email detector, not a userinfo URL.
        #expect(TypedContentDetector.url(in: "me@work.com") == nil)
    }

    // MARK: Email

    @Test("a whole-query email address fires")
    func emailFires() {
        #expect(TypedContentDetector.email(in: "me@work.com") == "me@work.com")
        #expect(TypedContentDetector.email(in: "first.last+tag@sub.example.co") == "first.last+tag@sub.example.co")
    }

    @Test("a single trailing punctuation mark is tolerated on an email")
    func emailToleratesOneTrailingPunctuation() {
        #expect(TypedContentDetector.email(in: "me@work.com,") == "me@work.com")
    }

    @Test("prose containing an email never fires")
    func proseWithEmailDeclines() {
        #expect(TypedContentDetector.email(in: "email me@work.com please") == nil)
        #expect(TypedContentDetector.email(in: "me@work") == nil)
    }

    @Test("the mailto URL composes to the address")
    func mailtoComposes() {
        #expect(TypedContentDetector.mailtoURL(forEmail: "me@work.com")?.absoluteString == "mailto:me@work.com")
    }

    // MARK: Phone

    @Test("a separated local number is a phone")
    func localNumberIsPhone() {
        #expect(TypedContentDetector.phone(in: "555-1212") == "555-1212")
    }

    @Test("a formatted and an international number are phones")
    func formattedAndInternationalArePhones() {
        #expect(TypedContentDetector.phone(in: "(555) 123-4567") == "(555) 123-4567")
        #expect(TypedContentDetector.phone(in: "+1 555 123 4567") == "+1 555 123 4567")
    }

    @Test("a run of too few or too many digits is not a phone")
    func digitBoundsGatePhone() {
        #expect(TypedContentDetector.phone(in: "2026") == nil)          // a year — 4 digits
        #expect(TypedContentDetector.phone(in: "3.14") == nil)          // a number — 3 digits
        #expect(TypedContentDetector.phone(in: "1234567890123456") == nil) // 16 digits — over the bound
    }

    @Test("prose around a number never fires as a phone")
    func proseWithNumberDeclines() {
        #expect(TypedContentDetector.phone(in: "call 555-1212") == nil)
    }

    @Test("the tel and sms URLs collapse separators, preserving a leading +")
    func dialURLsCollapseSeparators() {
        #expect(TypedContentDetector.telURL(forPhoneDisplay: "(555) 123-4567")?.absoluteString == "tel:5551234567")
        #expect(TypedContentDetector.smsURL(forPhoneDisplay: "555-1212")?.absoluteString == "sms:5551212")
        #expect(TypedContentDetector.telURL(forPhoneDisplay: "+1 555 123 4567")?.absoluteString == "tel:+15551234567")
    }

    // MARK: Bare copy/share value

    @Test("a tel/sms/mailto URL reduces to its bare recipient for copy/share")
    func bareValueStripsScheme() {
        #expect(TypedContentDetector.bareValue(forDetectedURL: URL(string: "tel:5551212")!) == "5551212")
        #expect(TypedContentDetector.bareValue(forDetectedURL: URL(string: "sms:+15551234567")!) == "+15551234567")
        #expect(TypedContentDetector.bareValue(forDetectedURL: URL(string: "mailto:me@work.com")!) == "me@work.com")
        // A mailto's headers are dropped — the address is the bare value.
        #expect(TypedContentDetector.bareValue(forDetectedURL: URL(string: "mailto:me@work.com?subject=Hi")!) == "me@work.com")
    }

    @Test("a web URL has no bare recipient — its own string is the value")
    func bareValueNilForWebURL() {
        // The Open row copies the URL itself, so there is nothing to strip.
        #expect(TypedContentDetector.bareValue(forDetectedURL: URL(string: "https://apple.com")!) == nil)
        #expect(TypedContentDetector.bareValue(forDetectedURL: URL(string: "http://example.org/x")!) == nil)
    }

    // MARK: Whitespace / empty

    @Test("empty and whitespace queries detect nothing")
    func emptyDetectsNothing() {
        for query in ["", "   ", "\n"] {
            #expect(TypedContentDetector.url(in: query) == nil)
            #expect(TypedContentDetector.email(in: query) == nil)
            #expect(TypedContentDetector.phone(in: query) == nil)
        }
    }
}
