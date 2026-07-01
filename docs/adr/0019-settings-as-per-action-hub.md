# Settings becomes the per-action hub with deeplinkable panels and generalized disable

## Context

Settings was deliberately scoped to "settings only": Appearance plus a thin
Actions section (New Event alone), while every content library (Quicklinks,
Fallbacks, Snippets, the Pile, Shortcuts, Indexed Folders) lived on its own
Management page reached by typing its name. We now want (a) an enable/disable
switch on nearly every action and (b) provider-specific options, discoverable
both from a unified Settings page and directly from results.

## Decision

Settings becomes a two-tier **per-action hub**. The top-level Settings page has
an **app-level** section and a **Providers** section (one navigation row per
Provider). Each row pushes that provider's **Management page**, which now
*unifies* what used to be two ideas — a per-action settings panel and a content
page — into one page with two sections:

1. **Options** — the provider's declared settings, with the provider-level
   **Enabled** toggle (the kind-level disable) as the first entry.
2. **Actions** — the provider's own actions, each with an enable/disable toggle
   (instance-level disable) plus swipe-to-delete where the action is deletable
   (permanent built-ins are disable-only). Providers with no enumerable
   instances (Calculator, File Search, capture actions) show only Options.

Every provider also surfaces one **Settings command row** whose main action
**deeplinks** into its page (`.openPage(.settings(panel:))`, extending the
existing `ManagementPage` / `.openPage` routing rather than a parallel
mechanism; `panel: nil` opens the top-level page). For content/capture
providers this *redirects* the former management-page command row to the unified
page; dynamic injectors that never had a row (Calculator, File Search) gain one.

**Disable** is generalized to all actions as a reversible hide (excluded from
typed results, Recents, and the Favorites grid; data retained), distinct from
delete, at the two levels above. A disabled kind short-circuits its instances.
**Settings itself is non-disableable** so the recovery path always exists.

## Consequences

- Reverses the "Settings holds only settings … not where you manage content"
  rule from the earlier model. The provider's settings and its content now live
  on one page; there is no separate content page and no **Manage …** link-out.
- The former Management page and the per-action settings panel collapse into a
  single concept, so there is one destination per provider instead of two.
- Enablement is new persisted state (kind + instance), keyed by a stable
  provider/action identity in the shared App Group defaults; the existing
  `FallbacksStore` disabled/order set is retained as Fallbacks' own
  instance-level state (no migration).

## Considered options

- **Keep Settings and Management pages fully separate** (twin destinations,
  cross-linked). Rejected: the request wants provider config reachable *as* a
  deeplink from results and a single hub, not two parallel trees.
- **Settings panel that links out to a separate content page** (a **Manage …**
  link). This was the first cut of this ADR; rejected in favour of one unified
  page per provider — a settings page that simply *is* the content page, with
  options above the action list — because the link-out added a hop and split one
  provider across two destinations for no real gain.
