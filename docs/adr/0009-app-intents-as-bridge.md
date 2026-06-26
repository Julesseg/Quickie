# App Intents is a bridge layer, not the engine

Quickie's core launching engine is its own model — Providers (Indexed and Dynamic), the custom forgiving matcher, and per-keystroke fuzzy ranking over a live, user-mutable index. This core is **not** built on Apple's App Intents framework.

App Intents are statically declared types resolved by the system; they do not model dynamic per-keystroke ranking over a mutable index with a custom matcher. Building the engine on App Intents would cripple the matcher and the Provider design. The two have different jobs: our engine does *in-app launching*; App Intents lets the *OS* invoke a few headline things (Spotlight, Siri, Shortcuts, Action Button).

So App Intents sits **on top** as a thin export bridge: our Providers are the source of truth, and we bridge a curated subset of Actions outward.

**v1 exposure (deliberately small):**

- A few **App Shortcuts** for headline verbs ("Quick Capture in Quickie" → open focused, "New Note", "New Reminder") for Siri / Spotlight / Action Button.
- **Favorites** exposed as dynamic App Shortcuts where feasible.
- **CoreSpotlight** indexing of all user content (notes/snippets/quicklinks) is deferred — later polish, not core.
