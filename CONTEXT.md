# Quickie

Quickie is an iOS launcher built around a single text input: the user types or taps, the app fuzzy-matches against a list of capabilities, and the user decides what to do with the input. "Input text and decide what to do with it after."

## Language

**Action**:
A single invokable capability shown in the fuzzy list (e.g. Open App, Web Search, Copy Snippet, Run Shortcut, Calculate). There is exactly one type of thing in the index — an Action — and every subsystem (fuzzy finder, indexing, favorites, fallbacks) operates on it. An Action has an execution lifecycle (selected → optionally collecting input → presenting results), so a multi-step capability is still a single Action, not a separate concept.
_Avoid_: Command, Workflow (reserved — see below), Item

**Workflow**:
Reserved term, not yet built. A future user-composed chain of multiple Actions into a pipeline. Do not use "Workflow" to mean a single multi-step Action.

**Fallback Action**:
Any Action (typically a placeholder-Quicklink) flagged to always appear in the result list and consume the user's literal typed text as its payload (e.g. "Search web for 'X'", "Create reminder 'X'"). Distinguished from a verb-first match, where the text fuzzy-matches an Action's name/alias. The single result list interleaves both; the user resolves intent by choosing a row, never by a mode toggle. Default web search is the built-in Fallback.
_Avoid_: Default action, catch-all

**Quicklink**:
A stored URL template with zero or more `{placeholder}` tokens. With no placeholder it is a static link that opens directly (Indexed Provider); with a placeholder it takes an Argument the typed text fills (e.g. `https://github.com/search?q={query}`). Opens in the user's system-default browser. Web search is a built-in placeholder-Quicklink, and any placeholder-Quicklink can be flagged a Fallback Action. Added via the Share Extension or manually.
_Avoid_: Bookmark, link, URL action

**Argument**:
A typed or picked value an Action consumes during its lifecycle. An Action declares zero or more. They are collected one slot at a time in the single bottom input field, with the active Action and filled slots shown as a breadcrumb/pill (`[New Reminder] ▸ "buy milk" ▸ …`). Verb-first selection clears the search query and prompts for the first Argument; noun-first (Fallback) selection passes the literal typed text in as the first Argument.
_Avoid_: Parameter, field, input (ambiguous)

**Snippet**:
A piece of saved text the user can quickly re-copy to the clipboard. The user-curated list is searchable as Actions and can be added to via the Share Extension. Snippets are the app's answer to "saved text"; Quickie deliberately has no automatic clipboard history (iOS forbids ambient clipboard access).
_Avoid_: Clipboard history, clip, stash

**Clipboard prefill**:
A launch-time offer to seed the input field with the current clipboard contents. Quickie silently checks only whether the clipboard *has text* (metadata, no system banner) and, if so, shows a tap-to-fill paste chip backed by the iOS Paste control — reading the actual content only on tap, never ambiently.
_Avoid_: Auto-paste, clipboard read

**Provider**:
A source that contributes Actions to the result list. Every Action originates from exactly one Provider. Providers are either Indexed or Dynamic.
_Avoid_: Source, Extension (collides with iOS app extensions), plugin

**Indexed Provider**:
A Provider whose Actions are a known, enumerable set, pre-indexed for fuzzy search and re-indexed only when its underlying data changes (Snippets, Quicklinks, Shortcuts, favorites, built-in commands). Queried from the in-memory index per keystroke.

**Dynamic Provider**:
A Provider that computes Actions on the fly from the current query and is never in the fuzzy index (Calculator, Unit Converter, File Search, Web Search / Fallbacks). Queried live per keystroke (debounced, cancellable, may be async), and decides for itself whether it applies to the query.

**Home**:
The empty-query state shown the instant the app opens: the Clipboard prefill chip (when applicable), a row of Favorites, then a Frecency list. The tap-without-typing fast path. Replaced by the Results state on the first keystroke.
_Avoid_: Landing, start screen, default view

**Favorite**:
An Action the user has manually pinned. Favorites appear as shortcuts on Home and receive a ranking boost in Results.
_Avoid_: Pinned, starred, bookmark (bookmark means Quicklink here)

**Frecency**:
The frequency × recency ranking signal derived from a user's past Action selections. Drives the auto-suggested list on Home and boosts ranking in Results. Distinct from Favorite (which is manual).
_Avoid_: Recents, history, MRU

**Shortcut Action**:
An Action that runs one of the user's iOS Shortcuts by name, via x-callback-url, capturing any returned output back into Quickie. Registered either by bulk import (via the Sync Shortcut) or one-by-one manual add — never enumerated through an API, which iOS forbids.
_Avoid_: Shortcut command, automation

**Sync Shortcut**:
A Quickie-provided iOS Shortcut the user installs and runs manually. It calls the Shortcuts `Get My Shortcuts` action to collect the names of all the user's shortcuts and returns them to Quickie via the `quickie://` URL scheme, populating the user's Shortcut Actions. Re-run to re-sync; there is no background/automatic refresh.
_Avoid_: Importer, bridge shortcut

**Indexed Folder**:
A folder the user has explicitly granted Quickie access to (via the document picker), persisted as a security-scoped bookmark. File search is bounded to the union of Indexed Folders — iOS forbids whole-filesystem or global indexing. Filenames within them are indexed for fuzzy matching; results open via QuickLook / share / open-in-place.
_Avoid_: Search scope, watched folder, library
