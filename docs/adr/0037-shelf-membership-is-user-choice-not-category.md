# Shelf membership is user choice, not an action category

## Context

The fallbacks overhaul (2026-08 grilling session) started from an intuition
that fallbacks split into two intrinsic kinds: **save-the-query** actions
(Reminder, Event, Save for later, note/todo captures) and
**search-with-the-query** actions (web search, Google Maps, any templated
search URL). The save kind was to get a preferential surface — the [[Shelf]],
a row of tinted glass buttons above the input — while the search kind stayed
in the bottom fallback region.

Making that split real would have required a category attribute on Actions.
The domain has already retired one such flag: fallback *eligibility* is
derived from shape, never stored (see [[Fallback Action]]). And a category
cannot be reliably derived — a text-first Custom Action is a notes-app deep
link or a search engine depending only on its URL, and a Shortcut with
accepts-input could be either — so a stored category would need a derivation
heuristic *plus* a user override *plus* migration rules.

## Decision

**There is no category.** The Shelf is a third tier of the existing promotion
ladder (pool → enabled → Shelf) on the [[Fallback list]], and Shelf membership
is the only fact — set by the user, defaulted on first run (New Reminder, New
Event, Save for later, New Snippet), never inferred from what the action *is*.
The capture-vs-search distinction survives only as the intuition behind those
defaults, not as model state. Nothing stops a user shelving Google Maps or
keeping a todo capture in the bottom region.

## Consequences

- No derivation heuristic, no override UI, no category migrations; the shelf
  list is stored and reconciled exactly like the enabled fallback list.
- The Shelf cannot filter or suggest by kind ("show me capture-ish actions
  when a slot is free") — deliberately out of scope; reversing this would
  mean introducing the category attribute this ADR rejects.
- Docs and UI must not name the tiers by kind ("save row", "capture shelf"
  were considered and rejected) — it is just the Shelf.
