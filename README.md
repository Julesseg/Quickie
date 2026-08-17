# Quickie

[![CI](https://github.com/Julesseg/Quickie/actions/workflows/ci.yml/badge.svg)](https://github.com/Julesseg/Quickie/actions/workflows/ci.yml)

iOS launcher built around a single text input: type → ranked Actions → do it.
See [`CONTEXT.md`](CONTEXT.md) for the domain language and [`docs/adr/`](docs/adr)
for the decisions behind the architecture.

## Project layout

```
Core/                      QuickieCore — platform-agnostic SwiftPM package (the loop's logic)
  Sources/QuickieCore/     ~58 focused sources, among them:
    Action.swift           the one kind of thing in the index + its main action
    ContentType.swift      typed content flowing through Quickie (ADR 0011)
    Provider.swift         the Indexed/Dynamic provider seam (ADR 0004)
    ProviderID.swift       each provider's stable, persisted identity (ADR 0019)
    Matcher.swift          forgiving layout-adaptive matcher (ADR 0005)
    SearchEngine.swift     match → rank → ranked Result list
    Frecency.swift         the recency/frequency ranking signal
    Argument.swift         breadcrumb Arguments + their input methods (ADR 0013)
    MultiStepAction.swift  an Action's selected → collecting → presenting lifecycle
    SecondaryAction.swift  long-press verbs keyed by Result content (ADR 0017)
    CustomActionDefinition.swift  user-authored URL Actions, slotted or static (ADR 0021, 0030)
    Catalog.swift          the read-only gallery of Custom Action templates (ADR 0028)
    FallbackActivation.swift / FallbackShelf.swift
                           which fallbacks are active, and which sit on the Shelf (ADR 0037)
    ComputedProvider.swift calculator, units, number bases, date & time and
                           time-zone conversion, typed-content detection (ADR 0032, 0036)
    FileSearchProvider.swift  search over user-designated Indexed Folders (ADR 0014, 0016, 0035)
    PendingQuery.swift     the Pile's auto-saved unresolved query (ADR 0018, 0031)
    MotionPolicy.swift / FeedbackPolicy.swift
                           the enumerated motion and haptic budgets (ADR 0010, 0034)
    WidgetAction.swift, EligibleActionCatalog.swift, FavoritesWidgetSnapshot.swift
                           what the widgets and controls project (ADR 0025, 0027)
  Tests/QuickieCoreTests/  Swift Testing suites — run with `swift test`

App/                       Quickie — thin SwiftUI/SwiftData iOS app (Xcode 26, iOS 26)
  Quickie.xcodeproj
  Quickie/                 the app target
    QuickieApp.swift       app entry, attaches the App Group ModelContainer
    RootView.swift         the screen: input + Shelf + reversed list + tap-to-run
    InputBar.swift         bottom auto-focused input, morphs per Argument
    ResultListView.swift   reversed, bottom-anchored Result list (ADR 0008)
    HomeView.swift         empty-query Home — Favorites grid over Recents
    SettingsView.swift     Settings hub: app prefs + one row per Provider (ADR 0019)
    ProviderPages.swift    the per-provider Management pages (ADR 0020)
    CustomActionsView.swift / CustomActionEditorView.swift / CatalogView.swift
    FallbacksView.swift, SnippetManagerView.swift, PileView.swift,
    ShortcutsView.swift, SystemView.swift, FileSearchContextView.swift, …
    AppShortcuts.swift     headline App Shortcuts for Siri/Spotlight (ADR 0024)
    Quickie.entitlements   App Group + CloudKit entitlements
  QuickieStoreKit/         the SwiftData schema, shared by app + extensions (ADR 0022)
  QuickieEntry/            code shared with the widget extension — the brand glyph,
                           colors, deeplink inbox, and widget-facing stores (ADR 0033)
  QuickieWidgets/          widget extension: deep-link, Favorites, and Actions widgets,
                           Quick Capture + Action controls, Pending-query Live Activity
  QuickieShareExtension/   share sheet → Custom Action / Snippet / Pile (ADR 0022)
  QuickieUITests/          XCUITest acceptance suites (run in CI, sharded)
  Scripts/                 build-stamp phase + the CI check that keeps it wired

docs/
  adr/                     architecture decision records
  agents/                  agent-facing skills (issue tracker, triage, domain docs)
  brand/                   app icon + mark generators, checked by CI
ci/                        installable-PR-build pipeline docs and helpers
```

The split is deliberate: all the loop's logic lives in `QuickieCore`, a pure
package testable on any platform, while the iOS app is a thin shell that wires
that logic to SwiftUI/SwiftData. The app depends on the package as a local
Swift package (`../Core`). Even presentation constants that have arithmetic —
the motion cadences, the haptic budget, keyboard geometry — live in Core so they
stay under the `swift test` gate.

## Building & testing

### Core logic (no Xcode required)

```sh
cd Core
swift test
```

This runs the full behavior suite — matcher, Action model, provider engine,
ranking, breadcrumb Arguments, fallback activation, widget projections — the
"type → ranked result → run" loop minus the pixels. This is the fast local loop.

### The app

Open `App/Quickie.xcodeproj` in **Xcode 26** (iOS 26 deployment target) and run
on an iOS 26 simulator. The `Quickie` scheme builds the app, its extensions, and
runs the `QuickieUITests` XCUITest target.

From the command line:

```sh
cd App
xcodebuild test -project Quickie.xcodeproj -scheme Quickie \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Pre-boot the simulator first — a cold headless boot can fail with "Timed out
waiting for AX loaded notification".

**App Group setup:** the store lives in the shared App Group
`group.com.julesseguin.quickie` (see `QuickieStoreKit/QuickieStore.swift` and the
`.entitlements` files), so the app, Share Extension, widgets, and App Intents all
write to one source of truth. On a real device you must enable the App Groups and
iCloud/CloudKit capabilities for the bundle ID (`com.julesseguin.quickie`) in your
Apple Developer account and set your signing team. The simulator runs without that
step — the store degrades gracefully when the group isn't provisioned. Only the
content store syncs via CloudKit; signals, settings, ordering, and Indexed-Folder
grants stay per-device (ADR 0023).

## Continuous integration

`.github/workflows/ci.yml` runs on every PR (GitHub-hosted runners, no Mac of
your own needed). Docs-only changes skip CI entirely.

- **Core · swift test (Linux)** — runs `cd Core && swift test` in the official
  `swift:6.0.3` container. Fast and cheap; covers all the loop's logic.
- **Brand · generated assets in sync** — re-runs the generators in `docs/brand/`
  and fails on drift, including the color literals hand-copied into
  `QuickieBrand.swift` and the accent color asset (ADR 0033).
- **App · build stamp wiring** — checks the git-commit stamp phase is still
  wired into the app target, so installed builds stay identifiable.
- **App · XCUITest (macOS)** — selects the latest stable Xcode and runs
  `xcodebuild test` for the `Quickie` scheme on an iOS simulator. The suite is
  **sharded across several macOS runners** (ADR 0026): a plan job partitions the
  `*UITests` classes from source — so a newly added suite can never silently run
  in no shard — and a final gate job checks that every shard passed. Every shard
  runs **once per device family**, against an iPhone and an iPad simulator
  (ADR 0038), because Quickie ships universal and the two families lay it out
  differently. Failed tests are retried up to three times to absorb simulator
  launch flakes.

> **UI tests run in CI only — by design.** XCUITest needs an iOS simulator that
> exists only on macOS, so the `QuickieUITests` target runs on the hosted macOS
> CI job, not as a local precondition for implementing an issue. Local iteration
> leans on `QuickieCore`'s `swift test` suite (the loop's logic, runs anywhere);
> CI's XCUITest job covers the UI behaviors on every PR. This split is the
> intended workflow, not a gap to close. See [`AGENTS.md`](AGENTS.md).

### Installable PR builds

`.github/workflows/release.yml` additionally builds a **signed, installable
`.ipa`** per PR (on the hosted `macos-15` runner) and publishes it to a GitHub
Pages site, so you can install any PR's build on your iPhone or iPad from
Safari. See
[`ci/README.md`](ci/README.md) for the one-time signing secrets / Pages setup.

## Providers

Everything in the index is an Action, contributed by a Provider. Each Provider is
configured on its own full-screen **Management page** — settings and content in
one — reachable by typing its name or from the Settings hub (ADR 0019).

| Provider | What it contributes |
| --- | --- |
| **Custom Actions** | User-authored URL Actions with zero or more `{slot}`s — slotted ones fill via the breadcrumb, slot-less ones are static links. Seeded on first run; extendable from the **Catalog**. |
| **Fallbacks** | Not a source of Actions but the surface that decides which eligible Actions consume the typed query, in what order, and which sit on the **Shelf** above the input (ADR 0037). |
| **Snippets** | Stored text, copied on run. |
| **Pile** | Queries saved for later, including the auto-saved pending query. |
| **Shortcuts** | Shortcuts imported by name via the companion Sync Shortcut (ADR 0007). |
| **System** | Umbrella over Reminders and Events capture, App Store Search, and Open iOS Settings (ADR 0029). |
| **Computed** | Calculator, offline unit conversion, number bases, date & time and time-zone conversion, and typed-content detection, injected with boosted rank (ADR 0015, 0032, 0036). |
| **File Search** | Files under user-designated Indexed Folders (ADR 0014, 0016, 0035). |

Every provider can be disabled at the **kind** level, and most at the **instance**
level too — reversibly, keeping its data. Settings itself is non-disableable so
the recovery path always exists.

## Entry surfaces

Beyond opening the app: a static deep-link widget, an interactive Favorites
widget, a user-chosen Actions widget, Quick Capture and Action Control Center
controls, a Pending-query Live Activity, four headline App Shortcuts for
Siri/Spotlight/the Action Button, a derived App Intents bridge over Favorites and
Custom Actions (ADR 0009, 0024), and a Share Extension.

## Status

M1 (the core loop), M2 (ecosystem in/out), and M3 (reach & depth) have shipped;
work since has been depth on top — the Catalog, the System umbrella, the Shelf,
and the brand/motion pass. See [`ROADMAP.md`](ROADMAP.md) for what each milestone
covered and what remains in the Later bucket, and
[GitHub issues](https://github.com/Julesseg/Quickie/issues) for work in flight.
