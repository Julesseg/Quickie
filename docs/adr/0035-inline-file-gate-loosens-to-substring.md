# Inline file gate loosens from strong (prefix) to substring matches

Status: accepted. Amends the inline-gate detail of ADR 0015 — the ranked-dynamic
split itself, the inline cap, and the Search Files context are untouched.

## Context

ADR 0015 gated File Search's inline rows on the **strong-match threshold**
(`Matcher.strongMatchThreshold`, 0.80) — the same constant the `SearchEngine`
uses for its top-tier boundary — so only an exact or prefix match of a filename
could surface while typing a normal query.

In practice that gate proved too strict: files felt like they needed an exact
match to surface at all. Typing `port` never surfaced `report.pdf` inline, even
though the filename plainly contains the query — the user had to enter the
Search Files context to find it. The matcher's tiers already distinguish the
case we want: a **buried substring** (base 0.60) is a contiguous, deliberate
match, unlike a scattered subsequence (≤ 0.55) or a typo (≤ 0.35).

## Decision

Gate File Search's inline rows on a new `Matcher.substringMatchThreshold`
(0.60, the buried-substring base): a filename **containing** the query — exact,
prefix, or mid-name substring — surfaces inline; scattered and typo hits remain
confined to the uncapped Search Files context (ADR 0014).

`Matcher.strongMatchThreshold` (0.80) stays, and stays the `SearchEngine`'s
top-tier boundary — the two thresholds now name different guarantees. Both are
defined *as* the subsequence tier's bases in `Matcher.subsequenceScore`, so the
tier boundaries and the gates built on them cannot drift apart.

## Consequences

- Substring file hits (0.60–0.75) sit **below** the engine's strong tier, so an
  exact or prefix command/Quicklink name still outranks them — the ordering
  guarantee ADR 0015 exists for is preserved; only the file gate loosened.
- The inline cap (~3 rows) is unchanged and does the flood-control work the
  stricter gate no longer does.
- Typos in filenames still require the Search Files context: the forgiving
  Damerau-Levenshtein tier tops out at 0.35, well below the gate.

## Considered options

- **Lower `strongMatchThreshold` itself to 0.60.** Rejected: it also defines the
  SearchEngine's no-boost-crosses-it top tier, so buried-substring matches of
  *every* action would have been promoted into the exact/prefix tier —
  a ranking change far beyond "surface files more easily".
- **Drop the inline gate entirely (cap only).** Rejected: scattered and typo
  hits would compete for the ~3 inline slots on nearly every query, crowding
  out the genuinely intended matches the cap is meant to show.
