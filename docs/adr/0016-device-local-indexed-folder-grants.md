# Indexed-Folder grants are device-local security-scoped bookmarks, never synced

## Context

Issue #49 (the foundation slice of File Search) lets the user grant Quickie
access to folders it may later search — **Indexed Folders** (CONTEXT.md → Indexed
Folder). iOS forbids whole-filesystem access, so a grant is captured as a
**security-scoped bookmark** minted from the folder the user picks in the system
document picker.

Everything else the user creates — Notes, Snippets, Quicklinks, Fallback queries
— lives in the shared App-Group SwiftData store, which is designed to gain
CloudKit sync later (ADR 0006). The obvious move would be to store folder grants
there too. But a security-scoped bookmark is **opaque and device-specific**: it
encodes a reference that only the device (and keychain) that minted it can
resolve. Syncing one to another device produces a bookmark that never resolves —
a dead grant that looks live.

## Decision

Store Indexed-Folder grants in a **device-local, non-synced** file — a plain
JSON file of `{id, displayName, bookmark}` records in the App-Group container —
kept **out** of the CloudKit-syncable SwiftData store. The App-Group container is
still used (so a future File Search extension reads the same grants on-device),
but the grants never ride CloudKit.

Grants are resolved with **staleness handling**: on load every bookmark is
resolved, and a grant whose bookmark no longer resolves is **pruned** rather than
shown as a dead row. Removing a grant revokes access by discarding its bookmark.

## Consequences

- Grants behave as "per-device Indexed-Folder grants" (the roadmap's wording): a
  folder granted on iPhone is not silently carried, unresolvable, to iPad.
- The store is a deliberately separate persistence surface from SwiftData. A
  reader should not "consolidate" folder grants into the model container later —
  that would reintroduce the cross-device dead-reference problem this ADR exists
  to avoid.
- Because bookmarks are the source of truth for *what the app may open*, the
  bounded resolve-and-prune on load keeps the list honest without a background
  reconciler.

## Considered options

- **Store grants in the SwiftData store (with CloudKit off for now).** Rejected:
  the store's whole point is to gain sync later; parking device-specific opaque
  bookmarks in it is a latent bug the day sync turns on.
- **Sync only a folder path/identifier, re-mint the bookmark per device.**
  Rejected for this slice: iOS gives no API to silently re-grant access to a path
  the user picked elsewhere — access must be re-granted through the picker on each
  device anyway, so a per-device store is the honest model.
