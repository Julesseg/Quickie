# Run the XCUITest suite on both device families

## Context

Quickie ships universal — `TARGETED_DEVICE_FAMILY = "1,2"` on every target —
and the ad-hoc provisioning profile now carries an iPad's UDID, so an iPad is
a device the installable PR builds land on.

Every UI test the project has ever run in CI ran on one iPhone simulator. The
resolver picks the last name in the family, which on the hosted runner is an
iPhone SE — deliberately the tightest screen, and the reason several suites
carry "on a short screen a row can land outside the fold" scroll helpers.

An iPad is not a bigger iPhone SE. It is a **regular**-width size class where
an iPhone in portrait is compact, and SwiftUI adapts on that boundary rather
than on point count: a sheet becomes a form sheet inset from the edges, a
menu becomes a popover, a navigation stack can become a split view, and the
keyboard can be undocked or split. Screen width alone changes what a test
sees: the [[Shelf]]'s peek cue is a pure rule pinned in `QuickieCore`, but
whether the row overflows at all — and whether a fallback lands above or
below the fold, which is what half the suite's scroll helpers exist for — is
decided by the device it runs on. None of that is covered by a suite that
only ever ran compact, so an iPad-only layout regression reaches the device
with every check green.

## Decision

**Every shard runs once per device family.** The `ui-test-plan` job computes
the class split exactly as ADR 0026 describes, then emits its `include`
entries once for `iPhone` and once for `iPad`. `device` is both the check's
name and the prefix its simulator is resolved by — every simulator in a
family is named after it — so the two legs share one code path and one
planner, and a newly added suite is picked up for both families at once.

**The gate check name does not move.** `app-ui-tests-gate` still carries
`App · XCUITest (macOS)` and still `needs` the whole matrix, so the families
are shards of the same matrix as far as branch protection is concerned. This
is the same invariant ADR 0026 established: shard jobs may be renamed, added
or removed — the required check may not.

**The legs are independent.** `fail-fast: false` already keeps a red shard
from cancelling its siblings; it now also keeps an iPad-only regression from
hiding every iPhone result. The xcresult artifact and result-bundle path
carry the device as well as the shard, because `upload-artifact@v4` rejects a
name a sibling job in the same run already claimed.

**Each family resolves to its tightest device.** The resolver takes the last
simulator name in the family, which lands on an iPhone SE and an iPad mini —
where a row below the fold or a clipped sheet shows up first. It now **fails
loudly** when the family has no simulator on the runner, rather than falling
back to a hardcoded `iPhone 16`: a leg that silently ran the other family's
simulator would be a green check for nothing.

**The matrix is sized to the concurrency cap, not to the shard count we would
like.** Doubling the families doubles the matrix, so `SHARD_COUNT` drops from
4 to 2 and the gate stays at four macOS legs. Measured on this repo's first
two-family run: only ~4 macOS jobs run at once (the account's cap, less the
slot the `Release` workflow's build job takes on the same PR), so 8 legs
queued into two waves — and each late leg still paid its own ~6 min build. At
a fixed cap of *k* concurrent runners, the wall clock is roughly
`total-test-time / k + build`, and every shard past *k* adds a build to that
sum without adding parallelism. Four legs of ~58 tests therefore finish
*sooner* than eight legs of ~29, and bill four builds instead of eight.
`SHARD_COUNT` stays the one knob — raise it when the concurrent-macOS budget
rises, not before.

## Considered options

- **Run only the layout-sensitive suites on iPad.** Rejected: which suite is
  layout-sensitive is precisely what nobody can know before the failure. Any
  hand-kept list rots exactly the way a hand-kept shard list does — the
  failure mode ADR 0026 built the source-derived planner to make impossible.
- **Keep `SHARD_COUNT` at 4 and let the eight legs queue.** Tried first, and
  measured: four legs started, four waited. Finer shards buy nothing past the
  concurrency cap — the queued half arrives no earlier and each pays a second
  build — so this is slower *and* dearer than the four legs above. The
  per-family shard count is only worth raising with the cap.
- **One leg, on an iPad only.** The iPhone is the primary target and carries
  the compact-width behaviors — dropping it to buy the iPad trades one blind
  spot for a worse one.
- **Trust SwiftUI's adaptivity.** It is exactly the adaptive branches — form
  sheet, popover, split view — that no test has ever executed. Trusting the
  untested branch is what this ADR is undoing.
