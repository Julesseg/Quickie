# Shard the XCUITest suite across macOS runners, planned from source

## Context

The `App · XCUITest (macOS)` CI job runs the whole `QuickieUITests` suite
serially on one hosted `macos-15` runner. Each test pays a fresh
`app.launch()` and real UI time, landing around ~20s per test method, so the
job's wall clock grows linearly with the suite — ~18 min at 37 tests
(issue #79), pushing ~27 min at today's 65. The suite is the canonical UI
gate on every PR (AGENTS.md), so its wall clock is the floor on PR feedback
time.

A first sharding attempt (#81) was reverted (#88): splitting the job into
`App · XCUITest (macOS) [shard N/3]` checks broke the branch-protection
configuration, which required the old single check name — every shard-count
or naming change would invalidate it again.

Hosted macOS runners are small (~3 cores / 7 GB), and runner minutes are
free on this public repo.

## Decision

**Parallelize across runners, one simulator per runner — never within one.**
A `ui-test-plan` job (Linux, seconds) partitions the suite's test classes
into `SHARD_COUNT` shards and emits a job matrix; each shard is a separate
`macos-15` runner that builds the app and runs only its classes via
`-only-testing:` filters on a single simulator. `SHARD_COUNT` is the one
knob trading runner count for wall clock.

**The split is computed from source on every run, never hand-maintained.**
The plan job scans `App/QuickieUITests/**/*.swift`, weighs each test class
by its `func test` count, and greedily packs the heaviest class into the
currently lightest shard (longest-processing-time bin packing). Weighing by
test-method count matters: classes hold 1–8 tests, so round-robining whole
classes piles most of the work onto one runner and the wall clock barely
moves. A newly added suite is picked up and assigned automatically — there
is no shard list to update when adding tests.

**The planner enforces the suite convention loudly.** The Xcode test target
is a filesystem-synchronized group: every `.swift` file under
`App/QuickieUITests/` joins the bundle automatically, and every shard runs
`-only-testing:` filtered — so a test class the planner cannot address would
run in *no* shard, silently. To close that hole the plan job **fails** when
a file declares a test class not named `<Name>UITests`, or more than one
test class per file. The contract for adding a UI suite is therefore:
**one `final class <Name>UITests: XCTestCase` per file, anywhere under
`App/QuickieUITests/`** — follow it and sharding needs no thought; break it
and the plan job goes red in seconds with the offending file named, before
any macOS runner spins up.

**Branch protection requires one stable gate check, not the shards.** An
`app-ui-tests-gate` job carries the exact pre-sharding check name
`App · XCUITest (macOS)` and fails unless the plan and every shard
succeeded. Shard jobs can be renamed, added, or removed without touching
branch protection — this is what un-breaks the failure mode that reverted
the first attempt.

Shards run with `fail-fast: false` (a red shard must not hide whether the
rest are green, and each keeps its own crash log and
`ui-test-results-shard-N` xcresult artifact) and keep the serial job's
`-retry-tests-on-failure -test-iterations 3` flake absorption.

## Considered options

- **Same-runner parallel testing** (`-parallel-testing-enabled`, capped
  workers), the original #79 plan. Rejected on measurement: two cloned
  simulators starve each other on a ~3-core host — the job got *slower*
  (28m51s vs ~17m serial) and the CPU pressure crashed SwiftUI's renderer.
- **Build once, `test-without-building` shards.** Saves billed minutes but
  *worsens* wall clock: the ~4 min build serializes ahead of every shard and
  the DerivedData artifact upload/download eats the rest, while per-shard
  builds run concurrently anyway. Minutes are free on this public repo, so
  the only currency that matters is wall clock.
- **DerivedData caching.** Evaluated in #79: macOS cache restore/save eats
  most of the ~4 min build it would save.
- **A hand-maintained shard list** (explicit class → shard mapping in the
  workflow). Rejected: it rots — the silent failure mode is a new suite
  that runs nowhere, which is exactly what computing the split from source
  (plus the loud convention check) makes impossible.
