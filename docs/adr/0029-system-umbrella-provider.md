# System is an umbrella provider: sub-pages linked, not merged, with a cascading Enabled

## Context

Two new OS-integration built-ins needed a home — App Store Search (a slotted
public URL scheme, but wanted as a permanent built-in rather than a Catalog
entry) and Open iOS Settings (not expressible as a Custom Action at all: no
slot, and the target is `UIApplication.openSettingsURLString`, the only page
iOS exposes — a query-driven "search Settings" is infeasible even via private
API, which App Review rejects anyway). At the same time the top-level Settings
Providers list was to be decluttered by grouping Reminders and Events under
the same roof.

## Decision

A new **System provider** acts as an umbrella. Its Management page hosts the
two built-ins as its own actions and **links** to the unchanged Reminders and
Events pages via navigation rows (the schema's existing `link` kind) — their
options, action rows, and typed Settings command rows survive intact; only
their rows in the top-level Settings Providers list fold into System's one
row. Its Enabled toggle **cascades**: System off short-circuits every member
kind beneath it, while the members' own toggles keep working underneath —
Disabled gains an umbrella level above kind.

## Considered options

- **Flat merge** (one page absorbing all reminder + event options): a ~9-option
  flat list the schema renders without section grouping, and a single Enabled
  for the lot. Rejected as unscannable.
- **Small sibling System provider** (keep Reminders/Events top-level): every
  page stays focused but the Providers list grows instead of shrinking —
  rejected because decluttering that list was the point.
- **Flat merge after adding section grouping to the settings schema**:
  cleanest end state, rejected for growing the feature by an ADR 0020 schema
  change it doesn't need.
