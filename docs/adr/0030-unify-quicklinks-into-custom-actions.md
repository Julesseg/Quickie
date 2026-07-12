# Unify Quicklinks into Custom Actions: a slot count of zero is a static link

Status: accepted. Supersedes the static-Quicklink half of ADR-0013; extends
ADR-0021 (Custom Actions) and ADR-0022 (Share Extension).

## Context

Quickie modelled two nearly-identical concepts. A **Quicklink** (ADR-0013) was a
stored *static* URL with no `{slot}` that opened directly; a **Custom Action**
(ADR-0021) was a stored URL that *required* at least one `{slot}` the breadcrumb
fills. They differ only in whether the URL carries arguments — yet each had its
own storage table (`StoredQuicklink` vs `StoredCustomAction`), provider
(`.quicklinks` vs `.customActions`), Management page and editor, Share-Extension
branch, and Catalog eligibility (the Catalog was Custom-Actions-only, so the
default homepage links could not be listed there).

The `≥ 1 slot` requirement was the only thing keeping them apart. Dropping it
makes a Quicklink just a Custom Action with zero arguments.

## Decision

**A Custom Action is a URL with zero or more `{slot}` tokens.** Slot count picks
the shape, and the two are one concept end to end:

- **Zero slots — a static Custom Action** (the former Quicklink): its URL is
  already resolved, so it opens directly on a bare `run(input:)`, wears the link
  leading glyph (`ActionKind.quicklink`), declares `.quicklink(id:)` content
  (copy/share **and** Edit), and is **not** fallback-eligible.
- **One or more slots**: unchanged ADR-0021 behaviour — breadcrumb-filled,
  `.customAction(id:)` content (Edit alone), fallback-eligible when text-first.

`CustomActionDefinition.isValidForSave` no longer requires `hasSlot`;
`makeAction` factories the static Action for a slot-less template instead of
returning `nil`.

**Everything lives under Custom Actions.** The `.quicklinks` provider, the
Quicklinks Management page/editor, and the `builtin.quicklinks-page` command row
are removed; the single Custom Actions page lists and edits both shapes. A new
Catalog **"Sites"** category holds the static links (the three seeds plus a few
more), separate from the search entries of the same names.

**Storage is unified by migration.** `StoredQuicklink` stays in the schema
**read-only**; a launch-time `migrateQuicklinksToCustomActions` converts each
row into a slot-less `StoredCustomAction` under the **same id** (preserving pins,
Frecency, Fallback-list membership) and deletes the source — the self-healing,
flag-less `migrateNotesToPile` pattern (ADR-0018). It runs *before*
`seedDefaultCustomActions`, so an already-seeded `seed.link.*` link converts
first and is not double-inserted. The Share Extension now writes a
`StoredCustomAction` for a shared URL. The seed flag bumps to
`store.didSeedCustomActions.v4` for the grown seed set (adds `seed.link.youtube`,
`seed.link.gmail`, `seed.link.github` as slot-less seeds).

**The internal `.quicklink` enum cases survive.** `ActionKind.quicklink` and
`ResultContent.quicklink` are kept as the representation of the *static variant*
of a Custom Action — the minimal-risk way to preserve the link icon and the
copy/share/edit menu — but they carry no separate *product* concept; both
variants attribute to the one Custom Actions provider. `ActionKind.quicklink`'s
raw value stays `"quicklink"` because the Favorites-widget snapshot persists it.

## Consequences

- One concept, one store, one page, one editor; the default homepage links join
  the Catalog. All docs (CONTEXT.md, this ADR, ADR-0013) are updated.
- **Orphaned enablement keys (accepted):** any per-kind enablement/settings keyed
  by the retired raw string `"quicklinks"` is now dead. Harmless — nothing reads
  it — and not worth a migration.
- The static seeds are ineligible by shape, so `FallbackActivation.firstRunEnabledIDs`
  filters `CatalogSeed.all` to the fallback-eligible (templated) seeds.
- Because the `.quicklink` enum names persist as the static variant, code and
  tests that build a "simple URL Action" via `Action.quicklink(...)` keep working;
  the factory is re-documented as building a static Custom Action.
