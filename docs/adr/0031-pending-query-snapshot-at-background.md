# The Pending query is a snapshot at background time, decided at the next activation

## Context

Leaving the app with unresolved text in the root input used to mean one of two
bad fates: state preserved indefinitely (a stale query greeting the user hours
later) or, via an [[Entry surface]], silent discard. Issue #152 turns that text
into a **Pending query**: restored on a quick return, committed to the [[Pile]]
after 30 seconds or on any entry surface, with a Live Activity as its visible
lifetime. The question this ADR settles is the *mechanism*: how does an iOS
app, which may be suspended or terminated at any moment after backgrounding,
reliably decide between restore and commit?

## Decision

**Snapshot `(text?, timestamp)` to the App Group defaults on backgrounding;
decide at the next activation — warm foreground or cold launch — by comparing
timestamps.** The scenePhase `.background` transition writes a `PendingQuery`
blob (Core-encoded, `swift test`-covered); the next activation *consumes* it
(read-and-clear, so activation and an entry-surface deeplink racing for it
resolve it exactly once) and applies the pure Core resolution: a plain open
under 30 seconds keeps/restores, anything else resets and commits any pending
text to the Pile with the confirmation flash.

Consequences that fall out for free:

- **Termination loses nothing.** The snapshot is on disk before the app can be
  killed; a cold launch reads the same blob a warm resume would have.
- **A never-reopened app commits on next open**, whenever that is — the
  decision needs no code to run at the 30-second mark.
- **The toggle is trivial:** off writes no snapshot, so every downstream
  behavior (reset, commit, Live Activity) vanishes with one guard.

The text rides the snapshot only for a **plain root query**; a half-filled
breadcrumb or the [[Search Files context]] snapshots textless — their state
still resets after the window, but nothing is written to the Pile.

The **Live Activity is chrome, not mechanism**: it mirrors the unresolved
input itself — started on the first qualifying keystroke (so it is already
live when the user backgrounds, with no request-at-background lag), updated
per keystroke, ended when the query empties or resolves. Backgrounding only
arms its self-dismissal at the window's edge, riding the ~30 seconds of
`beginBackgroundTask` execution the system grants — comfortably covering the
window — and a return within the window disarms it. If the process dies inside
the window anyway, the expiration handler ends the activity a touch early, and
the next launch's reconcile sweeps any leftover; the restore/commit decision
never depends on the activity's code running.

## Rejected

- **A background timer deciding at the 30-second mark** (BGTaskScheduler or a
  scheduled local wake): iOS gives no guarantee the app runs at any particular
  moment after backgrounding, so the commit could silently never happen — the
  one failure mode the feature exists to eliminate. Timestamp comparison at
  activation is exact and needs no execution window.
- **Committing eagerly at background time, deleting on quick return**: writes
  a Pile entry (CloudKit-synced user content) for every app switch, then has
  to claw it back — a sync-visible churn and a race against another device
  staging the entry, versus one local defaults write.
- **In-memory state only** (decide on the warm-resume path): loses the text on
  termination, failing "no path silently destroys typed text".
- **Routing the Live Activity tap through `quickie://entry`**: that is an
  Entry surface and would *commit* the text the activity exists to bring the
  user back to. The tap is a plain open — no `widgetURL` at all — which is
  icon-equivalent and lands on the restored query.
