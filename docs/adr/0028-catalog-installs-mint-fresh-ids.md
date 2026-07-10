# Catalog installs mint fresh ids; only first-run seeds are fixed-id

## Context

The [[Catalog]] is a built-in gallery of Custom Action templates with a
per-entry Install button, and the default-seeded set grows from one action
(web search) to four (plus Wikipedia, YouTube, Google Maps). Two id regimes
were on the table, and they pull in opposite directions: fixed well-known ids
are what let `StoreDedup` collapse the rows two devices each seed before their
first CloudKit import lands (ADR 0023), but fixed ids for *manual* installs
force the Catalog to track an "installed" state and pose the
what-does-Restore-do-to-user-edits question.

## Decision

Split by path. The **first-run seed** keeps the ADR 0023 shape: fixed
`seed.*` ids, a bumped one-shot flag (v3) that inserts whichever seed ids are
absent exactly once, dedup on sync merge, and no resurrection after delete. A
**manual Catalog install** always creates a new row under a **fresh id** — it
never checks for an existing copy, so tapping Install twice yields two rows,
exactly like hand-creating two identical Custom Actions. The Catalog therefore
tracks no installed state (every entry always offers Install), and restoring a
deleted default is just installing again — a new identity, so id-keyed state
(Frecency, pins, `quickie://run/<id>` deeplinks) deliberately does not revive.

## Considered options

- **Install-when-absent with fixed ids everywhere**: one id rule and an
  "Installed" checkmark, but an edited row still counts as installed by id,
  inviting a "Reset to default" overwrite path that destroys user edits.
  Rejected for the footgun and the modified-state tracking it drags in.
- **Fresh ids everywhere, including seeds**: one rule, but every multi-device
  user ends up with a permanently doubled default set after their first sync
  merge — the exact bug ADR 0023 exists to prevent.
