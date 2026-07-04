# Share Extension: shared store framework, classify in Core

## Context

Quickie should accept a **URL** or **plain text** from any app's share sheet and
let the user turn it into a stored Action — a URL into a [[Quicklink]], text into
a [[Snippet]] or a [[Pile]] entry (issue #14, the M2 epic). The epic's own text
says "text → Snippet or **Note**", but ADR 0018 retired Note wholesale; read
throughout as **Snippet (default) or Pile entry**. Images and files are
explicitly deferred.

A Share Extension is a **separate target and process** from the app. Two facts
drive every decision here:

1. It cannot `import` the app module, so it cannot see the `@Model` types
   (`StoredQuicklink`, `StoredSnippet`, `StoredPileEntry`), `AppGroup`, or
   `QuickieStore` — all of which live in `App/Quickie/QuickieStore.swift`,
   compiled into the app target alone.
2. Two processes opening the **same** App Group SwiftData store must agree on a
   **byte-identical schema**, or the store is corrupt/ambiguous.

The App Group container itself was provisioned up front (ADR 0006), so the
plumbing target exists; what's missing is a way to *share the schema* and a
place to *put the classification logic*.

## Decision

**Slice the epic, infra first.** (1) Extension target + shared framework +
"appears in the share sheet and writes one item"; (2) URL → Quicklink; (3) text
→ Snippet/Pile. Slice 1 carries all the real risk (project-file surgery,
entitlements, CI building a new target), so it is de-risked on its own before the
per-branch UX.

**Extract a shared framework, `QuickieStoreKit`.** The `@Model` types,
`AppGroup`, and the container configuration move out of the app target into an
embedded framework that **both the app and the extension link**. One schema, one
container config, one source of truth for the store file both processes open.
Rejected alternatives below.

**Classification logic lives in `QuickieCore`, not the extension.** The rules —
URL-vs-text, "plain text that is itself a valid `http(s)` URL", the ~40-char
first-line [[Snippet]] title derivation, host-name defaulting for a Quicklink
name — are **pure functions** with no SwiftData or UIKit dependency, so they sit
in `QuickieCore` and are covered by the Linux `swift test` gate on every PR. The
extension becomes a thin shell that unpacks `NSItemProvider`s, calls those
functions, presents a small SwiftUI sheet, and writes through `QuickieStoreKit`.

**Classification rule:**
- Any attachment conforming to `public.url` → **URL branch → Quicklink** (URL
  wins even when Safari also supplies `public.plain-text`; the page title, if
  present, seeds the Quicklink name).
- Else `public.plain-text` that **parses whole as a web URL** → default to the
  **URL branch**, with a toggle to treat it as text instead (a plain-text URL is
  genuinely ambiguous; default to the "I shared a link" reading).
- Else `public.plain-text` → **text branch**, a sheet defaulting to **Snippet**
  with a segmented switch to **Pile**.

**Images/files are excluded by the `NSExtensionActivationRule`**, not rejected at
runtime — the extension only advertises for `public.url` and `public.plain-text`,
so it never surfaces Quickie for a photo. A runtime guard for odd mixed payloads
stays as a defensive fallback only.

**The app sees new items on foreground.** The in-memory index is rebuilt from the
store on launch (ADR 0006); additionally the app re-fetches and re-indexes when
its scene returns to `.active`. That covers cold launch and the "app was
backgrounded while I shared" case without any cross-process signaling. A live
Darwin-notification path is a possible later refinement, deliberately out of
scope.

**The extension requires the App Group; it does not degrade.** Where the *app*
falls back to a private local store when the group is unprovisioned (ADR 0006),
the *extension* **refuses and shows an error** — a silent write to a container
the app can never read is a fake "saved", worse than an honest failure.

## Consequences

- New embedded framework target hand-authored into `project.pbxproj` alongside
  the new app-extension target and its embed-in-app build phase; the extension
  gets its own entitlements carrying `group.com.julesseguin.quickie` and its own
  `Info.plist` with the `NSExtension` activation rules.
- Moving `QuickieStore.swift`'s types out of the app's synchronized group into
  `QuickieStoreKit` is a one-time refactor; the app imports the framework
  afterwards. The schema definition stops being app-private.
- The share-sheet integration itself (activation, `NSItemProvider` unpacking,
  `completeRequest`) is **not** covered by CI — XCUITest drives Quickie, not
  another app's share sheet. This is accepted: with the logic in Core, the
  untested shell is thin and manually verified on device / by the reviewer.
- Two processes write the same store; SwiftData's own file coordination handles
  concurrent access, but the schema must stay identical — which is exactly what
  the single `QuickieStoreKit` definition guarantees.

## Considered options

- **A second SwiftPM library in `Core/` for the store**, Apple-only via
  `#if canImport(SwiftData)`. Rejected: SwiftData isn't on Linux, so it could not
  join the `swift test` Linux job, muddying Core's "pure, Linux-testable"
  identity (ADR 0006 leans on that split). A framework keeps SwiftData out of the
  SwiftPM package entirely.
- **Add the store source files to both targets' membership**, no new framework.
  Rejected: with `PBXFileSystemSynchronizedRootGroup`s, per-file membership
  across two synchronized folders is fragile, and it yields two compiled copies
  of the `@Model` types — tolerable only while byte-identical, a latent
  schema-drift footgun on the shared store file.
- **Broad activation + reject images/files at runtime.** Rejected: Quickie would
  appear in the share sheet for a photo and then apologize, dangling a promise
  the epic explicitly defers.
- **Live cross-process (Darwin) notification** so a foregrounded app updates the
  instant the extension saves. Rejected for now: the realistic path is "share
  from app X, later open Quickie", where a foreground re-index suffices; the app
  isn't visible during another app's share sheet anyway.
