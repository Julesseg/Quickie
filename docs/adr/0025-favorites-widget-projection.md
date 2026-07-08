# The Favorites widget is a projection, not a second engine

## Context

Epic #16 adds entry surfaces. The interactive **Favorites widget** mirrors the
[[Favorites grid]] and its buttons run a Favorite's main action. A widget runs
in its own process: it cannot see app memory, its render budget is tight
("keep cold launch light" applies to the widget too), and anything it executes
headlessly runs outside the app. Three questions were settled in the #16
design grill: how buttons execute, where render data comes from, and whether
widget runs feed [[Frecency]].

## Decision

**Execution: a three-way split — as little Quickie as possible.** A button
behaves exactly like tapping the Favorite's result row, minus any Quickie UI
the row never showed anyway:

- A **Snippet** copies **in-place**: the intent writes the pasteboard with no
  app launch, reading the body fresh from the shared App Group store *at run
  time* — a stale widget snapshot can never copy stale text.
- A **Quicklink** or **Shortcut Action** **hands off directly**: the intent
  opens the URL in the browser / fires the `shortcuts://x-callback-url` run
  straight from the widget process. The browser or Shortcuts app opening *is*
  the main action; a Shortcut's `quickie://` callbacks land in the app
  unchanged, so output reinjection works exactly as an in-app run.
- Anything needing input or in-app UI (a [[Quick capture]], a slotted
  [[Custom Action]], [[Search Files context]]) opens the app
  **tap-equivalently** via `quickie://run/<id>` (ADR 0024); an id that no
  longer resolves degrades to clean [[Home]], never an error.

Rejected: bouncing every kind through the app first — a visible app-launch
hop that serves no purpose for actions whose main action never shows Quickie
UI.

**Rendering: an app-written snapshot.** The app is the single writer of a
small denormalized snapshot (per Favorite: id, title, glyph, kind, and the
hand-off payload — Quicklink URL, Shortcut name, Snippet id) in the App Group,
rewritten plus `WidgetCenter.reloadTimelines()` whenever pins or the
underlying actions change. The widget renders from the snapshot alone and
never opens SwiftData to draw. Rejected: joining `SignalsStore` pin ids
against the SwiftData store at render time — it loads the model container on
every timeline render, makes render cost scale with store size, and gives the
store a second live reader. Also rejected: embedding snippet bodies in the
snapshot so even the Copy intent skips SwiftData — that trades a run-time read
for stale copies.

**Signals: an outbox.** A widget-run selection counts toward Frecency — the
actions run most from the widget are precisely the user's most-favored — but
`SignalsStore` loads once at app launch and rewrites keys whole, so a direct
cross-process write would be clobbered by the app's next save. The widget
intent instead appends `(actionId, timestamp)` to a pending-events App Group
key; the app drains the outbox into `SignalsStore` on foreground. Frecency
stays single-writer. Rejected: not recording (a ranking blind spot exactly for
the most-used actions) and direct writes (last-writer-wins races).

## Consequences

- The widget extension stays a **projection**: it renders a snapshot and
  executes via intents and deeplinks — no matcher, no Providers, no engine
  code outside the app (ADR 0009's spirit, one surface further out).
- The in-place / hand-off / open classification, the snapshot codec, and the
  outbox merge are pure `QuickieCore` logic under the Linux `swift test` gate,
  beside the deeplink parse (ADR 0024).
- The app gains two small foreground duties: drain the outbox, and keep the
  snapshot fresh on every pin, edit, delete, or disable that touches a
  pinned action.
