import XCTest

/// What can be proven about **key commands** (CONTEXT.md → Key command; issue
/// #262) by driving the real app on a simulator — which turns out to be very
/// little, and this file exists mostly to say so, so the next person does not
/// spend the afternoon rediscovering it.
///
/// **XCUITest cannot drive a key command on an iOS simulator.** `typeKey` reaches
/// the app's *text input* — the canary below types an ordinary letter and it lands
/// in the search field — but a ⌘ chord and `esc` never fire any binding. That was
/// measured against four independent mechanisms, on both the iPhone and the iPad
/// CI shards, with identical results every time:
///
/// 1. the SwiftUI scene's `.commands` (the menu bar declaration),
/// 2. `.onKeyPress(.escape)` on the launcher,
/// 3. an in-view `.keyboardShortcut` on a Button in the launcher's hierarchy,
/// 4. `UIResponder.keyCommands` on the app delegate — plain UIKit, the oldest and
///    most direct path there is.
///
/// Four mechanisms failing identically while plain keys arrive fine is not a
/// binding bug: the synthesized press reaches the text-input path and not the
/// key-command path. So the six tests that once drove ⌘K / ⌘, / ⌘1–⌘4 / esc were
/// removed rather than left red — a test that can only ever fail measures the
/// harness, not the launcher.
///
/// What covers the feature instead:
///
/// - **QuickieCore's `KeyCommandTests`** own every decision — which keys are
///   claimed, that none collides with a system shortcut, which Favorite a slot
///   addresses, and what `esc` unwinds from each launcher state. That is the part
///   worth protecting from regression, and it runs on any platform in milliseconds.
/// - **A hardware keyboard on a real iPad** is the only way to confirm the wiring.
///   It needs doing by hand when this ships and after any change to
///   `QuickieKeyCommandDelegate` or `LauncherCommands`.
///
/// Do not "fix" this by adding a test seam that calls the handler directly: that
/// would assert the launcher can run its own code, which is never in doubt — the
/// open question is whether the *key* reaches it, and only a real keyboard answers.
final class KeyCommandUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-uitest-reset-signals"] + extraArguments
        app.launchArguments.append("-uitest-instant-motion")
        app.launch()
        return app
    }

    /// The measurement the rest of this file's reasoning rests on: a synthesized
    /// hardware key *does* reach the app, through the same `typeKey` call the
    /// removed tests used. Keep it — if this ever fails, the harness changed and
    /// the conclusion above is worth re-testing; if it ever starts passing
    /// alongside a working ⌘ chord, the removed tests can come back.
    @MainActor
    func testSynthesizedHardwareKeysReachTheApp() throws {
        let app = launchApp()
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "bottom input should exist on launch")
        input.tap()

        app.typeKey("s", modifierFlags: [])

        XCTAssertTrue(
            app.buttons["builtin.settings"].waitForExistence(timeout: 10),
            "a hardware key sent with typeKey should land in the focused input"
        )
    }
}
