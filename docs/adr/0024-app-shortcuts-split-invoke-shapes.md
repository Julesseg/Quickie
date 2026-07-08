# App Shortcuts: split invoke shapes over the single URL door

## Context

Implementing ADR 0009's bridge (epic #18). Two things had drifted since 0009 was
written, and the epic needed slicing, so the open questions were settled in a
design review before implementation:

1. **"New Note" no longer exists.** ADR 0009's v1 exposure list predates ADR
   0018, which retired Note wholesale. Its heirs are **Save for later** (silent
   Pile capture) and **New Snippet** — read 0009's "New Note" accordingly.
2. **The inbound plumbing now exists.** The app has a single inbound door — the
   `quickie://` scheme, parsed by pure `QuickieCore` types and dispatched by one
   `onOpenURL` at the app root (ADR 0007; Sync Shortcut imports and Shortcut run
   callbacks already ride it).

## Decision

**Headline set.** Four static App Shortcuts: **Quick Capture** (open the app —
launch already auto-focuses the input), plus the full [[Quick capture]] family:
**Save for later**, **New Reminder**, **New Event**.

**Split invoke shapes.** Save for later runs in the **background**: Siri
dictates the text and the intent writes the Pile entry silently to the shared
App Group store — the Share Extension's write pattern (ADR 0022), surfacing on
the next foreground re-index. That is true to its glossary meaning (silent, no
confirm step). New Reminder and New Event run in the **foreground**: they open
the app into the selected Action's breadcrumb at Argument 1 — dates, target
lists, and calendars are the breadcrumb's job, and duplicating that collection
in Siri parameter resolution would thicken the bridge 0009 wants thin.

**One inbound door.** Foreground intents steer the app by opening `quickie://`
deeplinks — `quickie://run/<action-id>` (tap-equivalent run) and `quickie://entry`
(the open-focused fresh-Home reset epic #16's entry surfaces ride) — parsed by a
pure `QuickieCore` type covered by the Linux `swift test` gate, dispatched by the
existing root `onOpenURL`. Rejected: an in-process intent router — a second
inbound path parallel to `onOpenURL`, with its routing logic stranded in the App
target outside Core's test gate.

**No separate `capture/*` routes** (amended after slice 1, issue #120). The quick
captures are already built-in command rows in the index (`builtin.new-reminder`,
`builtin.new-event`), and a `run/<id>` of a capture row *is* "open that capture"
— so `quickie://run/builtin.new-reminder` / `run/builtin.new-event` already mean
"open the Reminder/Event capture". A parallel `capture/reminder` / `capture/event`
family (in an earlier draft of this ADR and issue #120) would only duplicate two
ids behind a second verb; `run` is the one uniform verb. Consequence: because
`run/<id>` resolves against the **live** catalog, a capture reached this way honours
its provider's Enabled toggle (a disabled Reminders kind degrades to Home) — the
same graceful-staleness rule every other bridged id follows, which is the intended
behaviour, not a regression to design around.

**One dynamic entity.** Favorites *and* Custom Actions are exposed through a
single parameterized App Shortcut ("Run &lt;name&gt; with Quickie") over one
entity — the **Bridged Action** set: Favorites ∪ Custom Actions, minus anything
[[Disabled]], refreshed via `updateAppShortcutParameters()` whenever pins or
Custom Actions change. Invocation is **tap-equivalent**: the app behaves exactly
as if the user tapped that Action's result row (a Favorite runs its main
action; a Custom Action starts its breadcrumb). Rejected: separate
favorite/custom-action entities and phrases — the curation rule would live in
two places for no user-visible gain.

**Graceful staleness.** Siri/Spotlight can hold entities the app has since
dropped (unpinned, deleted, disabled). A `quickie://run/<id>` that no longer
resolves opens the app on plain Home — the same "prune, don't dangle" spirit as
dead Indexed Folder grants (ADR 0016). Disabled excludes an Action from the
bridged set, consistent with Disabled meaning hidden from *every* surface.

**CoreSpotlight stays deferred** — unchanged from ADR 0009.

## Consequences

- The epic splits into three slices, each independently green: (1) the
  `quickie://` deeplink family + Core parse + root dispatch, (2) the four
  headline App Shortcuts, (3) the Bridged Action entity + parameterized
  shortcut. Slices 2 and 3 are thin over slice 1 and independent of each other.
- Intent types live in the App target (App Intents is app-process,
  Apple-only); everything decidable — deeplink parsing, the bridged-set
  derivation rule — lives in `QuickieCore` where `swift test` covers it.
- The background Save for later intent is a second write surface on the shared
  store alongside the Share Extension, writing through `QuickieStoreKit`; the
  foreground re-index already covers visibility (ADR 0022).
