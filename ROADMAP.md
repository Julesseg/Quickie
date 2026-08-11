# Quickie Roadmap

Phased build plan. The *why* behind each decision lives in `CONTEXT.md` (glossary) and `docs/adr/`.

M1–M3 have shipped. Each milestone below is kept as it was planned, with notes
where a concept was renamed or absorbed on the way in — the ADR is always the
authority on the shape that actually landed.

## M1 — Core loop (walking skeleton) · shipped

Prove the central "type → ranked actions → do it" experience end to end, fully local.

- Bottom auto-focused input, reversed (thumb-anchored) result list
- Forgiving layout-adaptive matcher (subsequence + Damerau-Levenshtein + keyboard-adjacency + diacritic/alias normalization + trigram prefilter)
- Provider engine (Indexed + Dynamic) and ranking (fuzzy + frecency + favorite + provider weight; exact-match floats top; fallbacks pinned bottom)
- Home state: Favorites + Frecency
- Providers: Quicklinks (+ built-in web-search fallback), Snippets, Notes (in-app), Calculator + offline unit conversion
- SwiftData **local**, App-Group container (CloudKit off for now)
- Basic Liquid Glass UI over a quiet backdrop

No extensions, no sync, no system surfaces yet.

> **Shipped differently:** Quicklinks folded into **Custom Actions** as slot-less
> links (ADR 0021, 0030); Notes were replaced wholesale by the **Pile** (ADR 0018);
> Calculator became the **Computed** provider, absorbing typed-content detection
> (ADR 0032). Web search is no longer a privileged built-in but a default-seeded,
> deletable Custom Action.

## M2 — Ecosystem in/out · shipped

- EventKit quick captures (Reminder, Event); Note capture already native
- Shortcut Actions + the companion Sync Shortcut
- Share Extension (URL + text → Quicklink / Snippet / Note)
- CloudKit sync **on** for the content store only (ADR 0023 — signals, settings, order, and Indexed-Folder grants stay per-device)
- Entry surfaces: deep-link widget, interactive Favorites widget, Control Center control, Action Button

> **Landed beyond the plan:** an **Actions widget** and **Action control** over a
> published eligible-action catalog (ADR 0027), and a **Pending-query Live
> Activity** for the auto-saved query (ADR 0031).

## M3 — Reach & depth · shipped

- File search over user-designated Indexed Folders (inline-capped + dedicated mode)
- App Intents bridge (headline App Shortcuts + Favorites)
- Secondary-actions (long-press) groundwork + content-type → applicable-actions registry

> The registry landed keyed by **Result content** rather than content type
> (ADR 0017), and the inline file gate later loosened to substring (ADR 0035).

## Since M3 — depth on what shipped

Not a planned milestone; the work that followed the three above.

- **Settings as a per-action hub** — every provider gets one full-screen Management page unifying its settings and its content, driven by a declared settings schema (ADR 0019, 0020)
- **Kind- and instance-level disable** — a reversible off-switch everywhere, with the **System** umbrella provider cascading over Reminders and Events (ADR 0029)
- **Catalog** — a read-only gallery of Custom Action templates; installs mint fresh ids and keep no link back (ADR 0028)
- **Fallbacks overhaul** — eligibility derived from an Action's shape, activation and ordering owned by the Fallback list, and the **Shelf** above the input as pure user choice (ADR 0037)
- **Brand and motion pass** — an accent derived from the app icon with gold reserved for the hero row, a living backdrop, a rotating hint line, and an enumerated haptic budget (ADR 0033, 0034)
- **Computed depth** — number bases, localized date grammar, and offline time-zone conversion (ADR 0036)
- **CI** — XCUITest sharded across runners (ADR 0026), plus brand-asset and build-stamp drift guards

## In flight

- Per-action color from a curated palette ([#243](https://github.com/Julesseg/Quickie/issues/243))
- Shelf buttons tinted with that Action color ([#244](https://github.com/Julesseg/Quickie/issues/244))

## Later bucket

- Currency conversion (network rates + caching)
- CoreSpotlight indexing of user content
- Images/files in the Share Extension (URL + text today)
- Per-browser override for Custom Actions that open URLs
- Native Workflows (visual step-chaining over typed content I/O)
- File-transport fallback for the Sync Shortcut (large libraries)

## Cut (not planned)

App launching · automatic clipboard history · password management. See ADRs 0001–0003.
