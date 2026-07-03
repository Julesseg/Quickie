# Custom Actions: unified multi-slot URL templates, config beside the URL

## Context

We want user-authored actions that submit through an app's URL scheme — e.g.
Things' `things:///add?title=…&when=…` — with each templated slot collected as
a typed breadcrumb Argument (issue: URL-scheme custom actions). ADR 0013 had
split URL things into exactly two shapes: **Quicklink** (static) and **Fallback
query** (template, one implicit argument, consumes the typed text). The new
capability is a strict superset of the Fallback query.

## Decision

One unified concept, **Custom Action** (CONTEXT.md): a user-authored URL
template whose `{name}` slots become the breadcrumb's ordered, typed Arguments;
the final commit percent-encodes each value into its slot(s) and opens the URL.

- **Fallback query is retired, absorbed wholesale.** Web search becomes a
  default-seeded one-argument Custom Action with the fallback flag on. No data
  migration — pre-release, no users on the old storage; the seed is re-seeded.
- **The fallback flag is orthogonal and per-action**: always surfaced in the
  bottom fallback region (user-ordered, as before), and selection
  **seeds-and-commits** the typed query as Argument 1 through the normal
  engine — so a one-argument fallback still completes in one tap, and a
  multi-argument one continues at step 2. The flag requires Argument 1 to be
  free text. Every Custom Action is also startable verb-first (breadcrumb
  begins empty at Argument 1).
- **Tokens are plain `{name}` — all other config lives beside the URL**, not in
  a rich token grammar. Per-argument sub-objects carry: type (`text` default,
  `number` → numeric keyboard, `date` → picker, `choice` → fuzzy option list),
  choice options, date output formats (ISO defaults; overridable date-only and
  timed formats, e.g. Things' `yyyy-MM-dd@HH:mm`), and **fill order**
  (drag-to-reorder in the editor; defaults to URL-appearance order — the UI
  states this explicitly). Same name twice = one Argument filling both slots.
- **No optional slots.** Every Argument is required; the lighter variant is a
  second, shorter Custom Action (e.g. "Things Todo" vs "Things Todo → Inbox").
- **Editor is the validator** (non-empty name, parseable schemed URL after
  probe substitution, ≥ 1 slot, choices non-empty); runtime keeps the silent
  `.none` on the can't-happen fill failure, and app-not-installed surfaces as
  the same failure toast as the Shortcut x-error path (no `canOpenURL`
  pre-flight — arbitrary user schemes can't be whitelisted in
  `LSApplicationQueriesSchemes`). Live-detected argument rows mirror tokens
  hard: a token deleted from the URL drops its config immediately, no stashing.
- **Quicklink stays a distinct static concept** (that half of ADR 0013 stands),
  and a Custom Action is *not* a Quick capture — it hands off to another app.
  New `ProviderID.customActions` with a standard ADR-0019 Management page
  (create/edit); the Fallbacks page remains the ordering/disable surface.

## Considered options

- **A third concept beside Fallback query.** Rejected: a Fallback query is
  exactly a one-argument fallback-flagged Custom Action; coexistence means two
  editors, two storage models, and a permanent "which one is mine?" question.
- **Config encoded in the token grammar** (`{when:2:date(yyyy-MM-dd@HH:mm)}`,
  `{list:choice(A|B)}`) so the whole action is one shareable string. Rejected:
  pipes, parens, and format patterns inside a phone-keyboard URL field, plus
  two-way form↔token rewriting, cost far more than the shareability is worth —
  sharing can come later as an export format. This buries the original
  "whole config contained in the URL" idea deliberately.
