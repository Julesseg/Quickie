# Quickie Roadmap

Phased build plan. The *why* behind each decision lives in `CONTEXT.md` (glossary) and `docs/adr/`.

## M1 — Core loop (walking skeleton)

Prove the central "type → ranked actions → do it" experience end to end, fully local.

- Bottom auto-focused input, reversed (thumb-anchored) result list
- Forgiving layout-adaptive matcher (subsequence + Damerau-Levenshtein + keyboard-adjacency + diacritic/alias normalization + trigram prefilter)
- Provider engine (Indexed + Dynamic) and ranking (fuzzy + frecency + favorite + provider weight; exact-match floats top; fallbacks pinned bottom)
- Home state: Favorites + Frecency
- Providers: Quicklinks (+ built-in web-search fallback), Snippets, Notes (in-app), Calculator + offline unit conversion
- SwiftData **local**, App-Group container (CloudKit off for now)
- Basic Liquid Glass UI over a quiet backdrop

No extensions, no sync, no system surfaces yet.

## M2 — Ecosystem in/out

- EventKit quick captures (Reminder, Event); Note capture already native
- Shortcut Actions + the companion Sync Shortcut
- Share Extension (URL + text → Quicklink / Snippet / Note)
- CloudKit sync **on** (per-device Indexed-Folder grants; synced frecency)
- Entry surfaces: deep-link widget, interactive Favorites widget, Control Center control, Action Button

## M3 — Reach & depth

- File search over user-designated Indexed Folders (inline-capped + dedicated mode)
- App Intents bridge (headline App Shortcuts + Favorites)
- Secondary-actions (long-press) groundwork + content-type → applicable-actions registry

## Later bucket

- Currency conversion (network rates + caching)
- CoreSpotlight indexing of user content
- Images/files in the Share Extension
- Per-browser override for Quicklinks
- "Execute actions on a Note" and full secondary-actions UX
- Native Workflows (visual step-chaining over typed content I/O)
- File-transport fallback for the Sync Shortcut (large libraries)

## Cut (not planned)

App launching · automatic clipboard history · password management. See ADRs 0001–0003.
