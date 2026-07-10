# The Actions widget's membership lives in the widget configuration, fed by a published eligible-action catalog

## Context

The [[Actions widget]] and the [[Action control]] show a **user-chosen**
Action list — unlike the [[Favorites widget]], which mirrors an in-app surface
(the Favorites grid). That choice has to live somewhere, and the picker and
the render both run **out of process**, where the in-memory engine, SwiftData
`@Query` state, and `@AppStorage` don't exist. Two questions were settled in
the design grill: where the membership lives, and where the picker and the
widget render get their data.

## Decision

**Membership: the system configuration owns it.** The chosen list is a
per-instance `AppIntentConfiguration` parameter (one Action for the control's
`AppIntentControlConfiguration`), edited in the system Edit-Widget sheet /
Control Center configuration — no in-app page holds or mirrors it. The widget
exposes it as **four ordered, single-pick slots** (`slot1…slot4`), not one
multi-select array parameter: single-select slots give the Edit-Widget sheet a
one-item-at-a-time picker, an inherent cap at the grid's four, and an explicit
order (which slot holds each action) — a multi-select list offers none of these.
Each placed instance carries its own list, multiple instances come for free, and
the app never needs a "which widgets exist" model. Rejected: an in-app management page
writing an App Group snapshot per widget — it needs an identity scheme for
placed instances that WidgetKit doesn't expose, collapses all instances onto
one list, and rebuilds UI the system already provides.

**Data: a published eligible-action catalog, ids in the configuration.** The
app is the single writer of a second App Group snapshot beside the Favorites
one: the **catalog** of every eligible Action (every enabled Action that is
[[Standalone-runnable]] — all but a [[Pile]] entry or Save for later, whose silent
Pile write does nothing without a query), each entry in the same denormalized shape the Favorites
snapshot uses — id, title, glyph, kind, classified `WidgetExecution` —
rewritten (publish-only-on-change, paired with a `WidgetCenter` reload)
whenever the underlying set changes. The picker's `EntityQuery` enumerates it;
the timeline provider and the control's value provider **join the configured
ids against it** to render and to pick each button's execution lane. The
configuration stores ids only. Rejected: denormalizing title/glyph/execution
into the stored entity — it goes stale the moment an action is renamed or
edited, and the configuration can't be rewritten from outside. Also rejected:
opening SwiftData from the widget process to resolve ids — ADR 0025 already
rejected render-time store reads for the Favorites widget, and the same
reasoning holds one surface further out.

## Consequences

- The Actions widget and Action control stay **projections** (ADR 0025): they
  render an app-written snapshot and execute via the existing three-way-split
  intents and the Frecency outbox — no engine code outside the app.
- A stale configured id simply fails the join: the cell drops to the dashed
  empty-slot tap target, the control falls back to the app glyph and a
  clean-Home open — never an error (the ADR 0025 degrade, extended).
- The eligibility rule and the catalog codec are pure `QuickieCore` logic
  under the Linux `swift test` gate, beside the Favorites snapshot codec.
- The app gains one more foreground duty: keep the catalog fresh on any
  create, edit, delete, enable, or disable that touches an eligible Action.
- **The Action control can't do the three-way split; it opens the app
  tap-equivalently.** A Control Center control body is a single, non-branching
  `ControlWidgetTemplate` (WidgetKit's `ControlWidgetTemplateBuilder` exposes no
  `buildEither`, so no `switch`/`if` over the resolved lane), and one intent can't
  span the lanes either — a single `perform()` has one return type (can't mix the
  copy lane's `.result()` with the hand-off lane's `.result(opensIntent:)`), and
  `openAppWhenRun` is `static`, not per-lane. So the control runs the one intent that
  serves every eligible action — `RunFavoriteInAppIntent` (`openAppWhenRun`), the
  tap-equivalent open — and its Frecency rides the app's ordinary run path, not the
  outbox. The [[Actions widget]] keeps the full three-way split (its cells are
  ordinary SwiftUI `Button`s, which *can* branch); only the control is constrained.
