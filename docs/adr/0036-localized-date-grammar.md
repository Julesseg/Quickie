# The date grammar is dual-accept and hand-rolled, launching in four languages

## Context

The Date & time capability (CONTEXT.md → Date & time) parses natural phrases —
"3 weeks from friday", "days until dec 25", "9am PST in tokyo" — and the
obvious implementations were unavailable or rejected: `NSDataDetector` does
localized date parsing for free but is excluded from Core (its availability
wobbles across platforms, and the behavior suite must run under `swift test`
on Linux — the same reason `TypedContentDetector` is regex-based), and
third-party parsing libraries are out (ADR 0004's no-dependency stance). An
English-only grammar was considered and rejected: a launcher whose input *is*
language should understand the user's language, and the Units connector
(`to|in|as`) had already quietly baked English into the input grammar.

## Decision

The grammar is **hand-rolled** and **dual-accept**: one language-independent
parser skeleton (number + unit word + connector + anchor word) fed by
per-language keyword tables, where **English always parses** regardless of
device locale — it is what every hint, doc, and screenshot teaches, and
bilingual users mix — and the device language's table layers on top when we
ship one. Launch tables: **English, French, Spanish, German**. Weekday and
month names are not hand-written: they come from the system calendar's
localized symbols, so a table contributes only the ~15 connector/unit/anchor
words of its language. The same tables localize the Units connectors, so
"5 m en pieds" works alongside "5 m to ft". Output (the copied/staged answer)
formats per device locale — the grammar is dual-accept, the answer is not.

## Consequences

- Adding a language is data plus tests, not code: a new keyword table, no
  parser change.
- English phrases can never be broken by localization work — dual-accept makes
  English the compatibility floor.
- Ambiguity across the accepted languages resolves like everything else in
  Computed: branches are non-arbitrating, so a phrase valid in two grammars
  fires each interpretation's row and the user picks.
