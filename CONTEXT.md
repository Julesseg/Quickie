# Quickie

Quickie is an iOS launcher built around a single text input: the user types or taps, the app fuzzy-matches against a list of capabilities, and the user decides what to do with the input. "Input text and decide what to do with it after."

## Language

**Action**:
A single invokable capability shown in the fuzzy list (e.g. Open App, Web Search, Copy Snippet, Run Shortcut, Calculate). There is exactly one type of thing in the index — an Action — and every subsystem (fuzzy finder, indexing, favorites, fallbacks) operates on it. An Action has an execution lifecycle (selected → optionally collecting input → presenting results), so a multi-step capability is still a single Action, not a separate concept.
_Avoid_: Command, Workflow (reserved — see below), Item

**Workflow**:
Reserved term, not yet built. A future user-composed chain of multiple Actions into a pipeline. Do not use "Workflow" to mean a single multi-step Action.

**Fallback Action**:
A noun-first Action that is always present in the result list and consumes the user's literal typed text as its payload (e.g. "Search web for 'X'", "Create reminder 'X'", "Copy 'X'"). Distinguished from a verb-first match, where the text fuzzy-matches an Action's name/alias. The single result list interleaves both; the user resolves intent by choosing a row, never by a mode toggle.
_Avoid_: Default action, catch-all
