# The Fallback list lives on the Custom Actions page; the Fallbacks provider is retired

Status: accepted. Amends the "one Management page per Provider" shape of
ADR 0019 for one provider, and retires the Fallbacks provider it listed.

## Context

Since ADR 0019 the fallback region has been governed from its own **Fallbacks**
page, under its own `ProviderID.fallbacks` with its own kind-level Enabled
switch, while the **Custom Actions** page authored the actions that make up
nearly all of it. The Fallback list is cross-provider by design — it orders
text-first Custom Actions beside accepts-input Shortcut Actions and the four
built-in captures — so it seemed to want a page of its own. In practice the
two pages listed the same five seeded search actions twice, with different row
shapes and a different toggle rule, and a user had to learn which page held
which verb: authoring on one, activation on the other.

## Decision

**The Fallback list moves onto the Custom Actions page, and the Fallbacks
provider goes away.** The page reads, top to bottom: Options (the kind Enabled
switch, a **Fallbacks** on/off toggle, Browse catalog), then the three ladder
sections **Shelf**, **Active fallbacks**, **Available for fallback**, then
**Other actions** for the Custom Actions that are not fallback-eligible.
A fallback-eligible Custom Action is listed once, in whichever ladder section
it sits in. The captures and accepts-input Shortcuts are **guests** of the
ladder: they appear only in those three sections, and tapping one goes to its
own home (a Shortcut's settings page, a capture's provider page). The Shortcuts
page is untouched.

Three consequences were chosen deliberately rather than fallen into:

- **The Custom Actions kind switch silences the whole region**, captures and
  Shortcuts included, exactly as the retired Fallbacks switch did. This is the
  one place a kind switch reaches past its own instances (the System umbrella
  aside), recorded in the glossary's Disabled entry. The alternative — the
  kind switch hiding only Custom Actions while the region kept the captures —
  would have left a page whose master switch didn't master its own sections.
- **The page is permanently in edit mode** so the two ordered tiers show their
  grips, which forfeits swipe actions. Delete and Duplicate move into the
  Custom Action editor (Duplicate reopens the editor on the copy; Delete
  confirms), and a confirmed Delete joins the Shortcut settings page. An
  Edit button toggling edit mode was rejected as one more tap before every
  reorder; drag-without-grips was rejected as undiscoverable.
- **The old Fallbacks enablement value is not migrated.** The `fallbacks`
  key is orphaned as ADR 0030 orphaned `quicklinks`; a user who had switched
  Fallbacks off sees them return until they flip the new toggle. Accepted:
  the population is tiny and the recovery is one switch on the page they
  already know.

## Considered options

- **Keep both pages and cross-link them.** Rejected: the duplication is the
  complaint; a link makes it two hops instead of one.
- **Rename the page "Actions" and pull the Shortcuts list in too.** Rejected
  for now: it dissolves the provider model for every user-content kind at
  once, and the Shortcuts page carries import machinery (Sync, Re-sync,
  Remove all) that has nothing to do with fallbacks. Custom Actions stays
  the page's name and identity.
- **Keep `ProviderID.fallbacks` as a hidden provider for its switch.**
  Rejected: a provider with no page and no actions is a stranded concept; the
  switch is a declared option on the Custom Actions page instead.
