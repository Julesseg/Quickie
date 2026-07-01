# Importing the user's Shortcuts via a companion Sync Shortcut

iOS exposes no API to enumerate the user's installed Shortcuts (the same privacy wall as installed apps). Rather than force users to register every Shortcut Action by hand, Quickie ships a companion **Sync Shortcut** that does the enumeration from inside the Shortcuts app, where it *is* possible.

**Mechanism:**

- The Sync Shortcut uses the native `Get My Shortcuts` action to collect all the user's shortcuts, maps each to its **Name**, encodes the list, and returns it to Quickie via the `quickie://` URL scheme (`Open URL`).
- Quickie ingests the names and registers each as a searchable **Shortcut Action**. Triggering later goes through `shortcuts://x-callback-url/run-shortcut` with output captured via `x-success`.
- ~~Manual one-by-one registration remains as a secondary add-path.~~ **Cut during #13 scoping (2026-07):** the Sync Shortcut import is the *sole* on-ramp — there is no manual add. Rationale: a second registration path doubled the surface (its own UI, its own reconciliation rules against re-sync auto-prune) for a secondary flow; dropping it makes auto-prune universal by construction (every entry is imported, so no `imported`-vs-`manual` provenance to track) and concentrates design effort on one excellent import flow. Accepted cost: a user who never runs the Sync Shortcut has zero Shortcut Actions.

**Re-sync reconciliation (decided during #13 scoping):**

- Identity is the shortcut **name** (`Get My Shortcuts` returns no stable IDs). Re-sync matches stored entries against the incoming payload case-insensitively.
- **Auto-prune, universal:** a re-sync rebuilds the set to mirror the payload — new names are added, existing names are kept, and names absent from the payload are removed. The per-shortcut **`acceptsInput` toggle is preserved** for every surviving name.
- Corollary: **renaming a shortcut reads as delete + re-add** on the next sync (and drops its `acceptsInput` toggle with the old name). Accepted, same family as manual re-sync.

**Accepted limitations:**

- **Names only.** `Get My Shortcuts` yields names, not input/output schemas. Shortcut Actions are registered runnable-by-name; input is offered optionally and passed via x-callback when present.
- **Manual re-sync.** No background refresh — the user re-runs the Sync Shortcut when their library changes. Acceptable because shortcut libraries change rarely.
- **Delivery (decided during #13 scoping):** the Sync Shortcut is distributed as an **iCloud share link** (`icloud.com/shortcuts/<id>`) that "Install Sync Shortcut" opens, not a bundled `.shortcut` file — this decouples the Sync Shortcut from App Store releases so its encoding/self-filter/chunking can be iterated freely. The trade is a hosted artifact tied to the developer's Apple ID and the **"Allow Untrusted Shortcuts"** gate (below). If that gate proves an adoption killer, escalate to an Apple-signed/Gallery shortcut — not before.
- **One-time install friction** (importing the Sync Shortcut, possibly allowing untrusted shortcuts) and **filtering the Sync Shortcut itself** out of the imported list.
- **Transport:** URL-scheme round-trip first. If very large libraries overflow the URL, fall back to the Sync Shortcut writing a file into an Indexed Folder that Quickie reads. Not built unless it bites.

Recorded because the companion-shortcut workaround is non-obvious — a future reader would assume enumeration is either impossible or done through a (non-existent) API.
