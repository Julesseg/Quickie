# Importing the user's Shortcuts via a companion Sync Shortcut

iOS exposes no API to enumerate the user's installed Shortcuts (the same privacy wall as installed apps). Rather than force users to register every Shortcut Action by hand, Quickie ships a companion **Sync Shortcut** that does the enumeration from inside the Shortcuts app, where it *is* possible.

**Mechanism:**

- The Sync Shortcut uses the native `Get My Shortcuts` action to collect all the user's shortcuts, maps each to its **Name**, encodes the list, and returns it to Quickie via the `quickie://` URL scheme (`Open URL`).
- Quickie ingests the names and registers each as a searchable **Shortcut Action**. Triggering later goes through `shortcuts://x-callback-url/run-shortcut` with output captured via `x-success`.
- Manual one-by-one registration remains as a secondary add-path.

**Accepted limitations:**

- **Names only.** `Get My Shortcuts` yields names, not input/output schemas. Shortcut Actions are registered runnable-by-name; input is offered optionally and passed via x-callback when present.
- **Manual re-sync.** No background refresh — the user re-runs the Sync Shortcut when their library changes. Acceptable because shortcut libraries change rarely.
- **One-time install friction** (importing the Sync Shortcut, possibly allowing untrusted shortcuts) and **filtering the Sync Shortcut itself** out of the imported list.
- **Transport:** URL-scheme round-trip first. If very large libraries overflow the URL, fall back to the Sync Shortcut writing a file into an Indexed Folder that Quickie reads. Not built unless it bites.

Recorded because the companion-shortcut workaround is non-obvious — a future reader would assume enumeration is either impossible or done through a (non-existent) API.
