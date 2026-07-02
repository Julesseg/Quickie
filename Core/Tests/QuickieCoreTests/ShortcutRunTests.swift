import Foundation
import Testing
@testable import QuickieCore

// Running a Shortcut Action and getting its output back (CONTEXT.md → Shortcut
// Action; issue #46). The outbound side fires `shortcuts://x-callback-url/run-
// shortcut` by name with `quickie://` callbacks; the inbound side classifies the
// callback Quickie is reopened on into reinject / failure / silent-cancel. Both
// are pure so the whole round-trip is exercised without a device.
struct ShortcutRunTests {

    // Pulls a query item's value out of a built URL for assertions.
    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    @Test("running a shortcut opens run-shortcut by name with quickie:// callbacks")
    func runURLCarriesNameAndCallbacks() {
        let url = ShortcutRun.runURL(name: "Start Workout", input: nil)
        #expect(url.scheme == "shortcuts")
        // The x-callback-url run-shortcut endpoint, addressed by name.
        #expect(url.absoluteString.hasPrefix("shortcuts://x-callback-url/run-shortcut"))
        #expect(queryValue("name", in: url) == "Start Workout")
        // Success/error/cancel all point back at the app's own quickie:// routes so
        // the inbound `result(from:)` can classify whichever one fires.
        #expect(queryValue("x-success", in: url) == "quickie://shortcut-result")
        #expect(queryValue("x-error", in: url) == "quickie://shortcut-error")
        #expect(queryValue("x-cancel", in: url) == "quickie://shortcut-cancel")
    }

    @Test("with no input the run carries no text parameters")
    func runURLWithoutInputOmitsText() {
        let url = ShortcutRun.runURL(name: "Timer", input: nil)
        #expect(queryValue("input", in: url) == nil)
        #expect(queryValue("text", in: url) == nil)
    }

    @Test("with input the run passes it as the shortcut's text input")
    func runURLWithInputPassesText() {
        let url = ShortcutRun.runURL(name: "Translate", input: "bonjour le monde")
        // Shortcuts' x-callback contract: `input=text` selects the text source and
        // `text` carries the value (percent-encoding handled by URLComponents).
        #expect(queryValue("input", in: url) == "text")
        #expect(queryValue("text", in: url) == "bonjour le monde")
    }

    @Test("editing a shortcut opens open-shortcut by name, with no callbacks")
    func editURLOpensOpenShortcutByName() {
        let url = ShortcutRun.editURL(name: "Start Workout")
        #expect(url.scheme == "shortcuts")
        // The plain open-shortcut endpoint, addressed by name — the editor deeplink.
        #expect(url.absoluteString.hasPrefix("shortcuts://open-shortcut"))
        #expect(queryValue("name", in: url) == "Start Workout")
        // Opening the editor is fire-and-forget: no x-callback-url wrapper, so none
        // of the run's success/error/cancel callbacks ride along.
        #expect(queryValue("x-success", in: url) == nil)
        #expect(queryValue("x-error", in: url) == nil)
        #expect(queryValue("x-cancel", in: url) == nil)
    }

    @Test("a shortcut name with spaces and reserved characters is encoded safely")
    func editURLEncodesName() {
        // URLComponents percent-encodes the value, so a name with a space and an
        // ampersand round-trips intact rather than corrupting the query string.
        let url = ShortcutRun.editURL(name: "Log Food & Water")
        #expect(queryValue("name", in: url) == "Log Food & Water")
    }

    @Test("x-success reinjects the returned output as the new query")
    func successReinjectsOutput() {
        // The output Shortcuts appends to x-success (`result`) comes back to be
        // reinjected as the query — the matcher re-runs over it (issue #46).
        let encoded = "42 tasks done".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "quickie://shortcut-result?result=\(encoded)")!
        #expect(ShortcutRun.result(from: url) == .reinject("42 tasks done"))
    }

    @Test("an empty x-success clears the query to a fresh Home")
    func emptySuccessReinjectsEmpty() {
        // Reinjection is unconditional on success: empty output clears the field
        // rather than being ignored, so the user lands on a clean Home (issue #46).
        #expect(ShortcutRun.result(from: URL(string: "quickie://shortcut-result?result=")!) == .reinject(""))
        #expect(ShortcutRun.result(from: URL(string: "quickie://shortcut-result")!) == .reinject(""))
    }

    @Test("x-error is a failure, x-cancel is a silent no-op")
    func errorAndCancelClassify() {
        // x-error flashes a failure toast and leaves the query untouched; x-cancel
        // is silent (issue #46). Both are distinguished from a success here.
        #expect(ShortcutRun.result(from: URL(string: "quickie://shortcut-error?errorMessage=boom")!) == .failed)
        #expect(ShortcutRun.result(from: URL(string: "quickie://shortcut-cancel")!) == .cancelled)
    }

    @Test("a non-run URL is not a shortcut result")
    func nonRunURLsAreIgnored() {
        // The import route on the same scheme, and a foreign scheme, are not run
        // callbacks — the app root dispatches those elsewhere.
        #expect(ShortcutRun.result(from: URL(string: "quickie://import?names=Timer")!) == nil)
        #expect(ShortcutRun.result(from: URL(string: "https://shortcut-result?result=hi")!) == nil)
    }
}
