# Quickie

[![CI](https://github.com/Julesseg/Quickie/actions/workflows/ci.yml/badge.svg)](https://github.com/Julesseg/Quickie/actions/workflows/ci.yml)

iOS launcher built around a single text input: type → ranked Actions → do it.
See [`CONTEXT.md`](CONTEXT.md) for the domain language and [`docs/adr/`](docs/adr)
for the decisions behind the architecture.

## Project layout

```
Core/                      QuickieCore — platform-agnostic SwiftPM package (the loop's logic)
  Sources/QuickieCore/
    ContentType.swift      typed content flowing through Quickie (ADR 0011)
    Action.swift           the one kind of thing in the index + its main action
    Provider.swift         the Indexed/Dynamic provider seam (ADR 0004)
    IndexedProvider.swift   enumerable provider + built-in Actions
    Matcher.swift          naive subsequence/substring scorer (placeholder for ADR 0005)
    SearchEngine.swift     match → rank → ranked Result list
  Tests/QuickieCoreTests/  Swift Testing suites — run with `swift test`

App/                       Quickie — thin SwiftUI/SwiftData iOS app (Xcode)
  Quickie.xcodeproj
  Quickie/
    QuickieApp.swift       app entry, attaches the App Group ModelContainer
    QuickieStore.swift     SwiftData schema + shared App Group container (ADR 0006)
    RootView.swift         the screen: input + reversed list + tap-to-run
    InputBar.swift         bottom auto-focused input
    ResultListView.swift   reversed, bottom-anchored Result list (ADR 0008)
    HomePlaceholder.swift  minimal empty-query Home state
    Quickie.entitlements   App Group entitlement
```

The split is deliberate: all the loop's logic lives in `QuickieCore`, a pure
package testable on any platform, while the iOS app is a thin shell that wires
that logic to SwiftUI/SwiftData. The app depends on the package as a local
Swift package (`../Core`).

## Building & testing

### Core logic (no Xcode required)

```sh
cd Core
swift test
```

This runs the full behavior suite for the matcher, Action model, provider
engine, and ranking — the "type → ranked result → run" loop minus the pixels.

### The app

Open `App/Quickie.xcodeproj` in **Xcode 26** (iOS 26 deployment target) and run
on an iOS 26 simulator. The `Quickie` scheme builds the app and runs the
`QuickieUITests` XCUITest target.

From the command line (what CI runs):

```sh
cd App
xcodebuild test -project Quickie.xcodeproj -scheme Quickie \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

**App Group setup:** the store lives in the shared App Group
`group.com.quickie.shared` (see `QuickieStore.swift` and `Quickie.entitlements`).
On a real device you must enable the App Groups capability for the bundle ID
(`com.quickie.app`) in your Apple Developer account and set your signing team.
The simulator runs without that step.

## Continuous integration

`.github/workflows/ci.yml` runs on every PR (GitHub-hosted runners, no Mac of
your own needed):

- **Core · swift test (Linux)** — runs `cd Core && swift test` in the official
  `swift:6.0.3` container. Fast and cheap; covers all the loop's logic.
- **App · XCUITest (macOS)** — selects the latest stable Xcode and runs
  `xcodebuild test` for the `Quickie` scheme on an iOS simulator, exercising the
  UI acceptance criteria (auto-focus, filter, tap-to-run, Home).

## Manual QA checklist (issue #3 acceptance criteria)

The UI behaviors run only in Xcode/simulator. Verify:

- [ ] App builds and runs on an iOS 26 simulator
- [ ] Launch drops straight into the bottom input with the keyboard up (auto-focus)
- [ ] Typing `git` / `apple` / `wiki` filters and ranks the built-in Actions
- [ ] The Result list is reversed/bottom-anchored — best match nearest the input
- [ ] Tapping a result runs its main action (opens the URL)
- [ ] Clearing the query shows the minimal Home placeholder

## Status

This is the **M1 walking skeleton** (issue #3). The matcher and UI are
deliberately crude here and are replaced by later slices (forgiving matcher,
frecency/favorites ranking, fallbacks pinned bottom, Liquid Glass polish). See
[`ROADMAP.md`](ROADMAP.md).
