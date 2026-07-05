# CloudKit syncs stored content only; signals, settings, and list order stay per-device

## Context

ADR 0006 set the platform posture: SwiftData as source of truth, CloudKit
private-database sync "on by default, offline-first," with "most user data"
syncing — explicitly including Favorites, settings, and Frecency stats ("as
additive counters, so ranking feels consistent across devices"). The CloudKit
epic (#15) inherited that list.

The codebase has since diverged from that sketch in two ways:

- **What lives where.** The SwiftData store holds only the content models —
  Snippets, Quicklinks, Custom Actions, Pile entries (plus the legacy Note
  table kept for migration). Favorites, Frecency, app settings, the Fallback
  list order, both Disabled sets, and imported Shortcut names all live in App
  Group `UserDefaults`, which does not ride CloudKit. Syncing any of them
  would mean migrating that state into new synced record types.
- **What Frecency is.** ADR 0006 promised "additive counters," but `Frecency`
  is an event log (Action id + timestamp, capped at 500) whose decay is
  recomputed against *now* on every query. There are no counters to add.

Grilling the epic surfaced a judgment call underneath the plumbing question:
ranking signals and toggles are records of *how this device is used*. A
launcher's Frecency on an iPhone (quick lookups, capture) and on an iPad
(reading, files) legitimately differ, and merging them would let one device's
rhythm distort the other's ranking.

## Decision

CloudKit private-database sync covers **exactly the content store** — the one
App-Group SwiftData store holding Snippets, Quicklinks, Custom Actions, and
Pile entries. Sync is on by default and offline-first; absence of iCloud
degrades silently to the fully-functional local app.

Everything else is **per-device state and does not sync**: Favorites,
Frecency, app-level settings, provider options, the Fallback list order, the
Disabled sets (kind and instance), and imported Shortcut Action names.
Indexed-Folder grants remain device-local per ADR 0016 — and since grants
never leave the device, no cross-device "not available on this device" row
can exist; the epic's earlier wording to that effect is void.

This supersedes ADR 0006's sync scope: the "Frecency stats sync as additive
counters" bullet is retired, and "most user data syncs" narrows to "stored
content syncs."

Two consequences of content sync are part of the decision:

- **Staging a Pile entry consumes it everywhere.** Staging deletes the entry,
  and the delete syncs: a query saved on iPhone and dealt with on iPad
  disappears from both. Dealt-with is dealt-with, on every device.
- **The seeded web-search Custom Action must not duplicate.** The first-launch
  seed is guarded by a per-device flag, so a second device can seed before its
  first CloudKit import lands. The seed therefore uses a fixed, well-known id,
  and launch runs a dedup pass collapsing same-id rows to a deterministic
  winner. (CloudKit-backed SwiftData cannot enforce uniqueness, so this is
  convention plus reconciliation, not a constraint.)

## Consequences

- Enabling sync is one store-configuration change plus CloudKit schema
  compliance (every attribute optional or defaulted); no `UserDefaults` state
  migrates anywhere.
- A user's content is identical across devices; each device's ranking,
  ordering, and toggles reflect its own usage. A surface can mix the two
  (synced Custom Actions under a per-device order) — the order reconciles
  locally against whatever rows sync in, as `resolvedOrder(for:)` already
  does.
- If cross-device ranking consistency is ever wanted after all, the honest
  path is the event log, not counters: Frecency events are naturally
  mergeable as a union of insert-only rows. That door stays open; this ADR
  just declines to walk through it now.

## Considered options

- **Sync everything user-authored or user-intent** (content + signals +
  settings + order), per ADR 0006's original sketch. Rejected: requires
  migrating every `UserDefaults` surface into synced records (or a second
  transport like `NSUbiquitousKeyValueStore`), and flattens real per-device
  differences in usage rhythm into one merged profile.
- **Sync content plus the Fallback list order** (a synced singleton
  order-record with a deterministic winner on pre-sync duplicates).
  Workable, but the order spans two built-ins that are not SwiftData rows,
  and a synced order beside per-device disabled state splits one page's
  behavior in two. Dropped in favor of a clean content/state boundary.
- **Exclude Pile entries** (deferred queries as per-device scratch).
  Rejected: CloudKit sync is configured per store file, so excluding them
  forces a permanent two-store split and a data migration — to avoid
  cross-device consumption that is actually the Pile's core use case
  (capture on phone, deal with on iPad).
