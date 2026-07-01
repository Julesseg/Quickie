# Settings panels are a declared schema with a bespoke escape hatch

## Context

With every Provider gaining a settings page (ADR 0019), there are ~14 near-
identical panels: an Enabled toggle plus a few options. Hand-writing a bespoke
SwiftUI view per provider (as `EventSettingsView` does today) would scatter
that logic across the App target — untestable by `swift test`, the only place
UI logic runs off-device — and duplicate it ~14 times.

## Decision

Each Provider **declares its settings schema in `QuickieCore`**: an `enabled`
flag plus zero-or-more typed options — `toggle`, `choice` (static *or*
`dynamic`, the latter fed live options by the app), and `stepper`. This schema
drives the **Options** section of the provider's Management page; the provider's
**Actions** section (per-action toggle + swipe-to-delete) is a live list of its
Actions, not part of the schema (ADR 0019). A `link` case is kept only for a
genuine cross-reference to another page (e.g. File Search → Indexed Folders),
not for a provider's own content, which now lives in the same page.
`SettingsView` renders any Options section generically from that declaration. A
provider may supply a **bespoke sub-view escape hatch**, but only
for an option no schema case can express — the default is always the schema.
The live EventKit calendar / reminder-list pickers are a `dynamic choice`, not
the escape hatch, so nothing ships needing it today.

## Consequences

- Panel structure, defaults, and enablement live in Core and are covered by
  `swift test`; new providers get a panel for free by declaring their schema.
- One options type must be designed up front, and the `dynamic choice` case
  needs an app-side hook to supply live options.
- The escape hatch is a deliberate pressure valve; keeping it schema-first
  (rule: "schema unless no case fits") stops it becoming a bespoke-view dumping
  ground.

## Considered options

- **Bespoke view per provider.** Rejected: ~14 duplicate views, logic stranded
  in the untestable App target.
- **Pure declared schema, no escape hatch.** Rejected as too rigid for a
  launcher that will keep adding providers; a genuinely exotic panel would force
  an awkward schema contortion. The hatch costs little while unused.
