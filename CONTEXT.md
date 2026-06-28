# Quickie

Quickie is an iOS launcher built around a single text input: the user types or taps, the app fuzzy-matches against a list of capabilities, and the user decides what to do with the input. "Input text and decide what to do with it after."

## Language

**Action**:
A single invokable capability shown in the fuzzy list (e.g. Open App, Web Search, Copy Snippet, Run Shortcut, Calculate). There is exactly one type of thing in the index — an Action — and every subsystem (fuzzy finder, indexing, favorites, fallbacks) operates on it. An Action has an execution lifecycle (selected → optionally collecting input → presenting results), so a multi-step capability is still a single Action, not a separate concept.
_Avoid_: Command, Workflow (reserved — see below), Item

**Main action**:
The single default behavior an Action (or result row) performs when tapped — open a Quicklink in the browser, open a file, run a Shortcut, copy a math result. Every row in the result list is presented by its main action.
_Avoid_: Default, primary (use "main action")

**Secondary action**:
An additional action that operates on a specific result's content, reached by long-pressing the row (deferred feature). The eligible secondary actions are determined by the result's content type. This is the home for "execute actions on a Note" and cross-cutting content actions. Distinct from Fallback/content-on-the-text actions, which appear as their own rows rather than behind long-press.
_Avoid_: Context action, more actions

**Result list**:
The single, reversed (bottom-anchored, best match nearest the input/thumb) list shown while typing. Composed of: fuzzy name-matches over Actions, type-triggered results injected with boosted rank by Dynamic Providers (e.g. a math result on top), and Fallback Actions that consume the raw input text as content. All appear as ranked rows; nothing essential is hidden behind a gesture.
_Avoid_: Results, suggestions, search results

**Workflow**:
Reserved term, not yet built. A future user-composed chain of multiple Actions, where each Action's output content feeds the next Action's input (validated by content type), authored as visual step-chaining rather than a text DSL. Made possible by every Action declaring typed input/output content from day one. Do not use "Workflow" to mean a single multi-step Action.

**Content type**:
The kind of a value flowing through Quickie — text, url, file, number, etc. An item's content type determines which Actions are eligible for it (and their ranking), which secondary actions a result exposes, and — in a future Workflow — whether one Action's output can feed another's input.
_Avoid_: Data type, kind, payload type

**Fallback Action**:
Any Action flagged to always appear in the result list and consume the user's literal typed text as its payload, rather than matching by name. The umbrella over three concrete kinds: **Fallback queries** (URL templates), **New Note**, and **New Snippet**. Distinguished from a verb-first match, where the text fuzzy-matches an Action's name/alias. The single result list interleaves both; the user resolves intent by choosing a row, never by a mode toggle. Fallbacks live in one user-ordered, reversible list (see Fallback list) and each can be **disabled** (hidden from results) without being deleted.
_Avoid_: Default action, catch-all

**Quicklink**:
A stored *static* URL that opens directly in the user's system-default browser — no `{placeholder}` token, no typed text consumed (Indexed Provider). It matches by name/alias like any other Action. Templated, query-consuming links are a separate concept now — see Fallback query. Quickie ships **no default Quicklinks**; the user adds their own (via the Share Extension or the Quicklinks page).
_Avoid_: Bookmark, link, URL action, template (a Quicklink has no template)

**Fallback query**:
A stored URL template that **requires** at least one `{placeholder}` token and consumes the typed text as its query, opening the result in the browser (e.g. `https://github.com/search?q={query}`). One concrete kind of Fallback Action, managed on its own list page. Web search is a default-seeded Fallback query (a normal, fully deletable entry — a reset-to-defaults affordance may come later), not a privileged built-in. Like every Fallback it can be disabled without being deleted.
_Avoid_: placeholder-Quicklink (the placeholder capability no longer lives on Quicklink), search action

**Fallback list**:
The single user-ordered list of every Fallback Action (Fallback queries + New Note + New Snippet), managed on one page and persisted as an explicit order. It reads **most-important-first**: the top of the page is the fallback nearest the input/thumb in results. Because the Result list renders reversed, this page order is reversed when projected into the bottom (screen-top) fallback region. Each row can be **disabled** (kept in the list, hidden from results); rows can be reordered; only Fallback queries can be deleted, while New Note and New Snippet are permanent (disable-only). Replaces the previous alphabetical fallback ordering.
_Avoid_: Fallback settings, fallback order screen (it is one page, "Fallbacks")

**Argument**:
A typed or picked value an Action consumes during its lifecycle. An Action declares zero or more. They are collected one slot at a time in the single bottom input field, with the active Action and filled slots shown as a breadcrumb/pill (`[New Reminder] ▸ "buy milk" ▸ …`). Verb-first selection clears the search query and prompts for the first Argument; noun-first (Fallback) selection passes the literal typed text in as the first Argument.
_Avoid_: Parameter, field, input (ambiguous)

**Snippet**:
A piece of saved, reusable text whose primary action is **Copy** — canned replies, an address, a template the user pastes repeatedly. Stored in Quickie (SwiftData + CloudKit), searchable as Actions, addable via the Share Extension. Quickie deliberately has no automatic clipboard history (iOS forbids ambient clipboard access).
_Avoid_: Clipboard history, clip, stash

**Note**:
A captured free-text thought whose primary action is **Open/read** (with append and copy secondary) — the brain-dump target. Stored in Quickie (SwiftData + CloudKit), captured instantly and silently (no app switch). Sending a Note to Apple Notes is an optional export, not the default. Distinct from a Snippet (reusable copy-out text) though they share storage.
_Avoid_: Memo, Apple Note (that is the export target, not a Quickie Note)

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
The empty-query state shown the instant the app opens: the Clipboard prefill chip (when applicable), a **Favorites grid** pinned at the top of the screen over a progressive-blur band, and a Frecency "Recent" list that scrolls *under* that band. The tap-without-typing fast path. On the first keystroke the Favorites grid disappears and the live Result list takes the full height, still scrolling under the same blurred top band.
_Avoid_: Landing, start screen, default view

**Favorites grid**:
The 2×2 grid of small Favorite cards pinned at the top of Home over a progressive blur. Shows **at most four** Favorites, in pin order; it is the launch-time, tap-without-typing surface. Visible only on Home — it vanishes the moment the user starts typing, ceding the screen to results. Replaces the earlier horizontal Favorites chip row.
_Avoid_: Favorites row, favorites bar

**Favorite**:
An Action the user has manually pinned. Capped at **four** (the Favorites grid is 2×2); a fifth pin is refused until one is unpinned. Favorites appear in the Favorites grid on Home and receive a ranking boost in Results.
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
