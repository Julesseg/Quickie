# Ranked-dynamic vs boosted-dynamic providers

## Context

`SearchEngine` routes **every** Dynamic Provider's candidates into the
`boosted` region, which floats them above all name-matched Actions with no
scoring — on the premise that "dynamic candidates arrive already query-relevant"
(ADR 0004). That is correct for the Calculator: a math answer is unambiguously
the top hit.

It is wrong for **File Search** (issue #17). A fuzzy filename hit (`report.pdf`
for `rep`) is not inherently better than an exact command or Quicklink name
match, so auto-floating it to the top would bury the thing the user actually
named. Yet File Search must stay a Dynamic Provider — it owns its own filename
index and prefilters it so a large file set never floods the central catalog,
Home, or Frecency (which is what Indexed Providers feed).

## Decision

Split the Dynamic contract into two behaviours:

- **Boosted-dynamic** (Calculator) — type-triggered, floats to the top region,
  not scored.
- **Ranked-dynamic** (File Search) — owns and prefilters its own index, but its
  handful of survivors are **scored by the `Matcher` and placed in the ranked
  region by match quality**, subject to the existing strong-match threshold and
  an inline cap (~3 rows). Only strong filename matches surface inline; weaker
  ones appear only inside the Search Files context (ADR 0014).

An exact command name thus still outranks a fuzzy file hit, while genuinely
strong file matches surface inline.

## Consequences

- `ProviderKind` / `SearchEngine` gain the boosted-vs-ranked distinction; a
  ranked-dynamic provider's candidates flow through name-scoring and ranking
  rather than the boosted bypass.
- File results carry only `(bookmarkID, relativePath)` in a new `.openFile`
  outcome; the app resolves that to a security-scoped URL under a start/stop
  bracket and opens it via QuickLook — Core never touches the filesystem, the
  same defer-to-the-edge pattern as `.openNote` / `.createEvent`.
- The index is a **snapshot**: iOS caps simultaneously-open security-scoped
  resources, so the app brackets access per folder during a build pass
  (rebuild on launch, foreground, and grant change) and serves keystrokes from
  a plain in-memory index — it never rescans the filesystem while matching.
  Live file-system watching is deferred (it fights the resource-limit
  constraint).

## Considered options

- **Keep File Search boosted like the Calculator.** Rejected: files would
  outrank exact name matches, which is the opposite of what the user wants.
- **Make File Search an Indexed Provider** so the central engine ranks it.
  Rejected: its catalog can be tens of thousands of filenames, which would
  flood the central index and leak files into Home and Frecency.
