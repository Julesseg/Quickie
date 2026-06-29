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
The kind of a value flowing through Quickie — text, url, file, number, date, etc. An item's content type determines which Actions are eligible for it (and their ranking), which secondary actions a result exposes, the **input method** used when it is collected as an Argument (e.g. `date` → an in-place date picker), and — in a future Workflow — whether one Action's output can feed another's input.
_Avoid_: Data type, kind, payload type

**Fallback Action**:
Any Action (typically a placeholder-Quicklink) flagged to always appear in the result list and consume the user's literal typed text as its payload (e.g. "Search web for 'X'", "Create reminder 'X'"). Distinguished from a verb-first match, where the text fuzzy-matches an Action's name/alias. The single result list interleaves both; the user resolves intent by choosing a row, never by a mode toggle. Default web search is the built-in Fallback.
_Avoid_: Default action, catch-all

**Quicklink**:
A stored URL template with zero or more `{placeholder}` tokens. With no placeholder it is a static link that opens directly (Indexed Provider); with a placeholder it takes an Argument the typed text fills (e.g. `https://github.com/search?q={query}`). Opens in the user's system-default browser. Web search is a built-in placeholder-Quicklink, and any placeholder-Quicklink can be flagged a Fallback Action. Added via the Share Extension or manually.
_Avoid_: Bookmark, link, URL action

**Argument**:
A typed or picked value an Action consumes during its lifecycle. An Action declares zero or more. They are collected one slot at a time in the single bottom input field, with the active Action and filled slots shown as a breadcrumb/pill (`[New Reminder] ▸ "buy milk" ▸ …`). Each Argument declares a **content type** that determines its **input method**: the single input region morphs to the right control per step — the keyboard for free `text`, an in-place graphical picker for a `date`, and for a fixed set of options a **fuzzy-find that reuses the matcher and the reversed result list** (type to filter, best match nearest the thumb) — so the user is never typing a value the system could pick. Verb-first selection clears the search query and prompts for the first Argument; noun-first (Fallback) selection passes the literal typed text in as the first Argument.
_Avoid_: Parameter, field, input (ambiguous)

**Input method**:
The input control the single bottom field morphs into for the current Argument, chosen by that Argument's **content type**: the keyboard for `text`, an in-place graphical picker for a `date`, and a fuzzy-find over a fixed option set (reusing the matcher and the reversed result list) for a choice. The mechanism that lets one input region serve every Argument type without modes — the user never types a value the system could pick.
_Avoid_: Input mode, control, widget

**Snippet**:
A piece of saved, reusable text whose primary action is **Copy** — canned replies, an address, a template the user pastes repeatedly. Stored in Quickie (SwiftData + CloudKit), searchable as Actions, addable via the Share Extension. Quickie deliberately has no automatic clipboard history (iOS forbids ambient clipboard access).
_Avoid_: Clipboard history, clip, stash

**Note**:
A captured free-text thought whose primary action is **Open/read** (with append and copy secondary) — the brain-dump target. Stored in Quickie (SwiftData + CloudKit), captured instantly and silently (no app switch). Sending a Note to Apple Notes is an optional export, not the default. Distinct from a Snippet (reusable copy-out text) though they share storage.
_Avoid_: Memo, Apple Note (that is the export target, not a Quickie Note)

**Quick capture**:
An Action that creates a record from the bottom input *without leaving Quickie* — the family comprising **Note** (Quickie-stored), **Reminder** and **Event** (written to EventKit). Each is silent by default (no app switch) and collects its fields through the breadcrumb, honoring just-in-time permission (ADR 0012).
_Avoid_: Quick add, capture (ambiguous)

**Reminder**:
A quick-capture Action that creates an EventKit reminder from the breadcrumb — a **title**, an optional **due date** (with an alarm when a time is given; a date-only due date sets no alarm), and a target reminder **list**. Lives in the system Reminders store, distinct from a **Note** (a Quickie-stored thought). EventKit permission is requested just-in-time when the Action is activated, before data entry (ADR 0012).
_Avoid_: Todo, task, alarm

**Event**:
A quick-capture Action that creates an EventKit calendar event from the breadcrumb — a **title**, a **start** (a timed start defaults to a one-hour duration; a date-only start becomes all-day), and a target **calendar**. Silent by default; a setting instead opens the pre-filled system event editor for final review. EventKit permission is requested just-in-time on activation (ADR 0012).
_Avoid_: Appointment, meeting, calendar entry

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
