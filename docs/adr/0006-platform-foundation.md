# Platform foundation: iOS 26, SwiftData + CloudKit

**Minimum deployment target: iOS 26.** Quickie's identity is the modern Apple aesthetic (Liquid Glass) and deep ecosystem integration. Targeting iOS 26 gets Liquid Glass as a native system material (instead of a hand-maintained imitation that drifts from the real look), plus clean SwiftData, the latest App Intents, and the banner-free Paste control — with no back-compat scaffolding. The cost is excluding users not on the current major version; acceptable because the target audience skews current-OS and a small team benefits most from dropping the compat tax. Reversible by lowering the floor later if a specific older-device audience emerges.

**Store: SwiftData, source of truth.** Snippets, Quicklinks, Favorites, Frecency stats, settings, and Indexed-Folder bookmarks live in SwiftData. The fuzzy search index is an **in-memory derived cache**, rebuilt on launch from the store — never the source of truth.

**Sync: CloudKit private database, on by default, offline-first.** Most user data syncs across devices. Two deliberate exceptions:

- **Indexed-Folder grants are per-device, not synced.** A security-scoped bookmark is device-specific and will not resolve on another device, so the access grant is modeled as per-device state; each device re-picks its folders. (The folder *list* may surface as "not available on this device" rather than a dead bookmark.)
- **Frecency stats sync** as additive counters, so ranking feels consistent across devices.
