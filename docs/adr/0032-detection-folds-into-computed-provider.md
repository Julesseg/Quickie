# Detection folds into the Calculator, renamed Computed — not a standalone Detector provider

## Context

Typed-content detection (a whole-query URL / phone number / email address
injecting boosted rows: Open, Message + Call, Email) needed a Provider home —
every row belongs to exactly one Provider, and every provider carries a
Management page, a typed Settings command row, and kind-level enablement.
Detection's shape is exactly the Calculator's: type-triggered, boosted-dynamic,
"the query *is* the value", rows carrying bare values with the universal
copy/share menu.

## Decision

Detection joins the Calculator provider, which is renamed **Computed**: the one
boosted-dynamic provider whose rows are derived from the query text itself —
math, unit conversion, and detected URL / phone / email. The persisted
`ProviderID` raw value stays `calculator` (renaming the stored identity would
re-key kind-level state — the same convention that kept `.quicklink` as a raw
value after ADR 0030); only `displayName` and the page title become "Computed",
with "calculator", "converter", and "detector" kept as typed aliases of its
Settings command row. Its options section holds five per-type toggles — Math,
Unit conversion, URLs, Phone numbers, Email addresses, all default-on — under
the provider-level Enabled switch, so turning the three detection toggles off
restores the pre-detection Calculator exactly.

## Considered options

- **A standalone Detector provider**: one more Providers-list row, Settings
  command row, and Enabled toggle for what is conceptually the same behavior
  the Calculator already exhibits (interpreting the query itself rather than
  matching names). Rejected as provider bureaucracy duplicating an existing
  shape.
- **Folding into the System provider**: detection feels OS-ish, but System's
  charter is OS-*integration* actions (EventKit, Open iOS Settings), and its
  cascading umbrella toggle would suddenly also govern query parsing. Rejected
  for muddying both concepts.
