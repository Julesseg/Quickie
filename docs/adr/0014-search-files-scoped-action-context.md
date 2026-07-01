# Search Files is a scoped-Action context, not a mode toggle

## Context

Issue #17 (File search over Indexed Folders) calls for a *"dedicated Search
files mode"* for full browsing, alongside inline-capped matches in the root
list. Taken literally, a "mode" is a chrome toggle that flips the whole surface
between "normal" and "files" — exactly what the **Result list** invariant
forbids: *"the user resolves intent by choosing a row, never by a mode toggle"*
and *"nothing essential is hidden behind a gesture."*

## Decision

Model the dedicated file-browsing surface as a **Search Files context** entered
by **selecting a "Search Files" Action row**, reusing the existing **Argument**
breadcrumb mental model rather than introducing a UI mode. Once selected, the
input scopes to the file index alone — shown as a breadcrumb (`[Search Files] ▸
…`), full-height, uncapped — and every keystroke filters only filenames.

File Search therefore surfaces two ways, both from the same provider:

- **Inline-capped** — up to ~3 file rows, only on strong matches, interleaved
  into a normal query's results.
- **Search Files context** — the uncapped browsing surface, reached by choosing
  a row.

## Consequences

- The "dedicated mode" enters by choosing a row, so the "never a mode toggle"
  invariant stays intact — a future reader who sees a file-scoped input state
  will not think it contradicts the Result list rules.
- The Search Files context is *not* an Argument slot: an Argument collects a
  value and then commits to an effect, whereas this context maintains a live,
  ongoing filter that never commits a value. It borrows the breadcrumb
  presentation but is its own context kind — the app must not shoehorn it into
  the multi-step Argument-collection machinery.

## Considered options

- **A literal mode toggle / files tab** (status quo reading of the issue).
  Rejected: it reintroduces the chrome and hidden-state the whole app is built
  to avoid, and would be the only mode toggle in the product.
