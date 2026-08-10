# Shard the XCUITest suite per test method, capped at five runners

## Context

ADR 0026 sharded `QuickieUITests` across `macos-15` runners, splitting whole
test *classes* and bin-packing them by `func test` count. It worked, and then
it stopped scaling: a green run on `main` (31312716459) took **21m36s**, and
raising `SHARD_COUNT` would not have moved it.

Measured from that run's four shard logs:

| | shard 1 | shard 2 | shard 3 | shard 4 |
|---|---|---|---|---|
| build + install + sim boot | 224s | 279s | 198s | 629s |
| test execution | 954s | 724s | 710s | 476s |

Three facts fall out of it, and together they say "more shards" is the wrong knob.

**A class is indivisible, so the heaviest one is a floor.**
`CustomActionUITests` is 13 methods and 11m30s of test time — a quarter of the
suite's 48 min in one unsplittable lump. Replaying the planner over the real
per-test durations, class granularity lands on the *same* wall clock at 5, 6
and 8 shards — **15m30s** every time, because one runner is always doing
`CustomActionUITests` and nothing else helps.

**Five concurrent macOS jobs is a hard account-level cap.** A sixth shard does
not run alongside the others; it waits for a slot and finishes a whole
shard-length later. Under a fixed slot cap, finer shards are free — right up
to the cap, and strictly harmful past it.

**Per-shard fixed cost is now a third of the critical path.** Every shard
rebuilds (~2 min) and boots its own simulator, and each new shard pays it
again. The boot is the volatile part: usually ~90s, once 8m41s, and it lands
*after* the build because `xcodebuild` boots the destination only when it
reaches the test phase.

## Decision

**Shard per test method, not per class.** The plan job emits
`-only-testing:QuickieUITests/<Class>/<method>` filters. The floor drops from
the slowest class (~11m30s) to the slowest single test (~2m).

**Deal methods round-robin in source order — do not try to weigh them.**
Measured durations span 10s–123s, and the obvious source-visible proxy (count
of `tap`/`typeText`/`waitForExistence`/assertion calls in the body) correlates
at only r≈0.35 — weighing by it would be false precision. Round-robin over
source order spreads each class's methods across every shard, which is what
actually evens the load: predicted per-shard test time 697/520/512/575/574s,
within a hair of what a duration-weighted packer would achieve, using nothing
but what is visible in source.

Replaying every option over the measured durations, at `fixed + slowest shard`
where fixed is ~4 min of setup, build and boot (the model reproduces the
observed run: it predicts 21m23s for the config that ran in 21m36s):

| shards | classes by test count (before) | classes, perfectly packed | methods round-robin (after) |
|---|---|---|---|
| 4 | **21m23s** | 16m03s | 18m56s |
| 5 | 19m38s | 15m30s | **15m36s** |
| 6 | 16m58s | 15m30s | 13m00s |
| 8 | 15m30s | 15m30s | 12m15s |

Two things to read off it. At 5 shards the win is mostly *balance* — method
round-robin gets what only a duration-weighted class packer could, and no
planner can weigh classes by duration from source. And the class column stops
improving at 15m30s forever, which is why the floor has to go before any future
shard-count increase can pay for itself.

**`SHARD_COUNT` is 5 because that is the concurrency ceiling**, not because 5
balances nicely. The comment at the knob says so, so nobody "optimizes" it to 8
and makes CI slower.

**Start the simulator booting before the build, not after.** The resolver step
now picks a concrete device *id* from the newest available iOS runtime and
calls `simctl boot` immediately, so the boot overlaps the build instead of
following it. The destination switched from `name=…,OS=latest` to `id=…` for
this to be worth anything: with a name, `xcodebuild` may pick a same-named
device on another runtime and cold-boot *that* one, wasting the head start.
The boot is best-effort (`|| true`) — `xcodebuild` still boots the device
itself if it failed.

Expected wall clock: **~15m30s**, from 21m36s — a little under if the
overlapped simulator boot pays off.

## Consequences

The convention ADR 0026 enforces is unchanged and still enforced, for the same
reason: one `final class <Name>UITests: XCTestCase` per file, or the plan job
goes red in seconds naming the file. Method-level filters make the failure mode
it guards against no less silent.

A `*UITests` class with no `func test` methods is now simply left out of the
matrix instead of getting a filter that matches nothing. Same outcome, one
fewer no-op.

The suite's ~48 min of test execution is untouched — this ADR only stops
wasting it. At 5 shards the floor is now per-shard fixed cost (~3 min) plus
~10 min of tests, so the next real win is in the tests themselves: ~40s per
test average, with a 123s, a 102s, and a `Thread.sleep(forTimeInterval: 9)` in
`HomeBrandUITests` all sitting on the critical path.

## Considered options

- **Just raising `SHARD_COUNT` to 8.** The table above: 15m30s, the
  `CustomActionUITests` floor — and it never gets there, because past 5 the
  extra shards queue for a runner slot instead of running alongside.
- **Bin-packing classes by measured duration** instead of test count. Would
  need durations the plan job doesn't have (it reads source, not last night's
  xcresults), and fixes the balance without touching the floor — 15m30s at any
  shard count.
- **Splitting `CustomActionUITests` into smaller classes.** Treats one symptom
  by reshaping test code around a CI constraint, and the next heavy class
  re-creates it. Method-level sharding removes the constraint instead.
- **Building once and fanning out `test-without-building`.** Rejected in ADR
  0026 and still rejected: per-shard builds run concurrently, so serializing
  one build ahead of every shard adds to the critical path.
