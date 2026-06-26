# The result list, main actions, and secondary actions

The screen is built around a single **Result list** that is reversed and bottom-anchored: the input sits above the keyboard and rows stack upward with the best match nearest the thumb.

**Composition of the list (all as ranked rows):**

1. **Fuzzy name-matches** over the Action catalog — the base. This is the verb-first search.
2. **Type-triggered results** — when the input *value* parses as a recognizable type (e.g. a math equation), a Dynamic Provider injects a result with boosted rank so it floats to the top (the calculator answer), displayed as if it were a top fuzzy hit even though it isn't a name match.
3. **Fallback Actions** — Actions that don't match by name but consume the **raw input text as content** (Web Search runs the chosen engine with the typed text as the query). Any placeholder-Quicklink can be flagged a Fallback.

Nothing essential is hidden behind a gesture — the "other things you can do with the typed text" are rows.

**Main action vs secondary actions:**

- Every row has a **main action** = what tapping it does (open Quicklink, open file, run Shortcut, copy result). This is the only action needed to use a row.
- A row may also expose **secondary actions** via **long-press** — actions that operate on *that result's content*, eligible by **content type** (text → Copy/Search/Make-reminder/Append-to-note/Run-Shortcut-with…; url → Open/Copy/Make-Quicklink; file → QuickLook/Share). This is a **deferred** feature and the home for "execute actions on a Note." Building the content-type → applicable-actions registry once gives every text-bearing item these actions for free, and is the substrate for the future Workflow chaining.

The earlier "primary/secondary" framing was initially rejected, then reinstated once it was clear that content-on-the-typed-text actions are rows (always visible) while a *specific result's* content actions live behind long-press (secondary). Both coexist without conflict.
