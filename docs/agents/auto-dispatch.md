# Auto-dispatch: ready issues → Paseo agent sessions

Issues marked `ready-for-agent` get implemented automatically once nothing is
blocking them: a fresh Claude Code session is spawned for each one via
[Paseo](https://paseo.sh) on a self-hosted Mac runner. Sessions run on the Mac's
Claude subscription login (no API credits) and are visible in the Paseo
desktop/mobile apps.

## How it works

Two workflows split detection from execution:

1. **`unblock-dispatch.yml`** (GitHub-hosted, pure scripting) runs when an issue
   is closed as *completed*, or on a manual `workflow_dispatch`. It scans open
   `ready-for-agent` issues, parses each body's `## Blocked by` section (`- #N`
   bullets), and keeps the ones that are ready to work — never blocked, or with
   every blocker now closed. For each, it fires `agent-implement.yml` with the
   issue number and comments on the issue.
2. **`agent-implement.yml`** (self-hosted Mac runner) re-checks the issue, then
   fetches the Mac clone's remotes and runs `paseo run --detach --new-branch
   claude/issue-<N> --base origin/main --label agent-implement=<N> …
   "/label-and-implement-with-pr issue #<N>"` — unless another labeled session
   is still running on the Mac, in which case it spawns nothing (see below).
   The `/label-and-implement-with-pr` skill carries the workflow instructions —
   claim the issue with the `agent-dispatched` label, run `/implement` to build
   it per AGENTS.md, build a screenshot report with `/ui-report` when the change
   is user-visible, merge the base branch in, push, open a PR that closes the
   issue, then hand that PR to `/babysit-pr` (see below). `--detach` means the
   session runs under the Paseo daemon and outlives the (short) runner job; the
   worktree flags keep the session off the clone's own checkout.

   That skill, and the ones it calls, are not in this repo: a dispatched
   session runs on the runner Mac and uses the skills installed in that Mac's
   own Claude config (`~/.claude/skills/`). Keep the personal set current
   there.

### After the PR opens

The session does not end at `gh pr create`. `/babysit-pr` keeps it alive,
watching the PR: it fixes CI failures the branch caused, reruns flaky checks
(three per SHA), acts on review comments (fixing, or replying with an `[agent]`
prefix when it disagrees or needs an answer), and rebases onto `main` whenever
the branch conflicts with it or falls behind it. It stops when the PR is
merged or closed, when a blocker needs a human (it says so in a PR comment),
or after 24 hours. Between polls the watcher blocks on GitHub, so an idle
watch costs almost nothing; but each babysitting session is a live Paseo
agent until it stops.

The `agent-dispatched` label stays on throughout, and after the babysitter
stops with the PR still open: the issue is in flight until the PR closes it.

### Who applies `agent-dispatched`

The session does, as its first act — never the dispatcher. The label therefore
means *a session really started on this issue*, not *a session was asked for*.
That distinction matters when the Mac runner is offline: `agent-implement.yml`
then sits queued for up to 24 h and may never run at all. A label applied at
dispatch time would leave that issue looking claimed forever, holding an
in-flight slot with nothing working it.

Between dispatch and the session's first move nothing is labeled, so the
dispatcher reads the spawn runs themselves to fill the gap. A run of
`agent-implement.yml` holds its issue while it is queued or in progress, and
for a 30-minute grace period after it succeeds — long enough for the session to
boot and label the issue. A run that failed, was cancelled, or expired unclaimed
in the queue holds nothing, so the issue goes back in the pool and is dispatched
again on the next run. (Because the runs list is the guard, the dispatcher waits
for each run it fires to become visible before moving on.)

### Three sessions at a time on tyr

Sessions run on **tyr**, the self-hosted Mac, which carries three concurrent
sessions and not many more. So the in-flight cap is **3**, and the spawn job
checks the machine itself before starting anything: `paseo ls --global` on the
runner, narrowed to sessions this workflow labeled `agent-implement=<issue>`,
and if three of them are `initializing` or `running` the job spawns nothing
and leaves a notice.

Two layers, because they cover different holes. The dispatcher's cap decides
what to fire and knows nothing about the Mac — it cannot see a session started
by a manual `agent-implement` run, or one still winding down inside the
30-minute handoff grace. The host check is the load-bearing one, and it fails
closed: **force does not override it**, unlike the issue checks below, because
it stands for what the hardware can take rather than for bookkeeping that might
be out of date. To spawn while the Mac is full, stop a session in Paseo first
and re-run.

The check is machine-wide, not repo-wide: `--global` sees every session on the
daemon, so the other repos running this same workflow on tyr share the three
slots, which is what a limit on the hardware should do.

Two things deliberately do not count. `idle` sessions: an idle session has
finished its turn and costs the machine nothing while it waits to be archived.
And sessions this workflow did not start — the label is what identifies them,
so one you open on tyr by hand is invisible to the check, and opening one
next to three dispatched sessions puts four on the Mac anyway.

Because the check reads the label, it only works on a Paseo CLI that has both
`ls --global` and `run --label`. An older one would leave every session
unlabeled and count zero busy sessions forever, so the spawn job checks for
both flags and fails red rather than letting the limit quietly stop existing.

An issue skipped for a full host is not lost, but it is not instant either: its
spawn run succeeded, so it holds the issue for the 30-minute grace period and
then returns to the pool for the next dispatcher run. If a session frees a slot
inside that window, the dispatcher run its closing PR triggers still sees the
hold and defers again — a manual re-scan is the quick way to pick the issue
back up.

### The spawn-time re-check

A spawn job can sit queued for hours, so what was true when the dispatcher
fired it may not be true when the Mac finally picks it up. Before spawning
anything, `agent-implement.yml` fetches the issue again and does nothing if:

- **the issue is closed** — you finished it by hand while the Mac was asleep,
  and a session for it now would redo settled work; or
- **the issue already carries `agent-dispatched`** — a session is already on
  it, so this run is a duplicate that queued behind the first.

Both leave a notice on the run rather than failing it: nothing went wrong, the
work simply no longer needs doing. A manual run can override either check by
ticking **force**, which is how you re-dispatch an issue whose session died
holding the label. Force does not reach the host check above — a full tyr
stops the spawn either way.

### Scope rules

- Only issues labeled `ready-for-agent` are dispatched.
- An issue qualifies when **nothing blocks it** — either it lists no `- #N`
  bullets under `## Blocked by` at all, or every bullet it lists is closed.
- **Umbrella issues are always skipped**: epics (`[Epic]` title prefix) and
  specs (`Spec:` title prefix). A human slices these into per-milestone child
  issues; a single agent session should never attempt one.
- At most **3** issues are in flight at once — counting both issues that carry
  the `agent-dispatched` label and issues whose spawn run is still live —
  because three sessions are what tyr carries. Ready issues beyond the cap are
  deferred; because every dispatcher run re-scans every open `ready-for-agent`
  issue, they're picked up automatically on the next run, usually the one fired
  by a running session's PR closing its own issue. While the Mac is offline
  the cap applies to the queue, so at most three sessions wait for it.
- If a session gives up, it removes the issue's `agent-dispatched` label and
  comments — which frees a slot and makes the issue eligible again.

### Where sessions branch from

Every session starts on a fresh branch cut from **`origin/main`**, and the spawn
step fetches the Mac's clone immediately beforehand.

Both halves matter. Paseo branches off a ref in the clone at
`PASEO_PROJECT_DIR` and never fetches on its own, so left alone a session
inherits whatever that clone last saw. Nothing updates its local `main` — the
runner only ever adds worktrees — so it drifts further behind with every merge,
and sessions were starting from a `main` over a hundred commits stale. Basing on
the remote-tracking ref sidesteps the local branch entirely; fetching first is
what keeps that ref from being stale in its own right.

This does not replace the skill's own `git fetch origin main` and merge before
it opens the PR. Other sessions land work while a long one runs, so the base
still moves underfoot. Starting current just means a session reads today's code
on its first pass instead of rediscovering it at merge time.

Override the base with the `PASEO_BASE` repository Actions variable — any ref in
the clone, e.g. `origin/release`. An unresolvable one fails the run outright
rather than quietly branching somewhere else.

### Model, reasoning effort, permission mode, and base

Sessions default to **Opus 5 at high reasoning effort, in bypass mode, branched
off `origin/main`**. Four optional repository Actions variables override that
without touching the workflow (Settings → Secrets and variables → Actions →
Variables):

| Variable         | Default              | Passed as    |
| ---------------- | -------------------- | ------------ |
| `PASEO_MODEL`    | `claude-opus-5`      | `--model`    |
| `PASEO_THINKING` | `high`               | `--thinking` |
| `PASEO_MODE`     | `bypassPermissions`  | `--mode`     |
| `PASEO_BASE`     | `origin/main`        | `--base`     |

Leave a variable unset (or set it empty) to fall back to the default — unlike
`PASEO_PROJECT_DIR`, none of the four are required. The defaults are pinned in
the workflow rather than inherited from the Paseo daemon, whose own defaults
move as new models ship.

See the current legal values with `paseo provider models claude` (efforts are
per-model, currently `low`/`medium`/`high`/`xhigh`/`max`/`ultracode` on the
Opus and Sonnet lines). Modes come from the provider:
`plan`/`default`/`acceptEdits`/`auto`/`bypassPermissions`.

`bypassPermissions` is the default because nobody is around to answer a
permission prompt in a detached CI session — the provider's own default
(`default`, "Always Ask") would stall the session on its first tool use until
the daemon times it out.

**The workflow validates the model and effort before spawning**, because
`paseo run` itself does not: given an unknown `--model` it creates the session
anyway rather than erroring, which would leave a typo'd variable silently
running every issue on the wrong model. So the spawn step checks the pair
against `paseo provider models claude --json` first and fails red — listing the
valid values — instead of dispatching. `--mode` and `--base` need no such
check; the CLI rejects an unknown mode outright, and a base ref it cannot
resolve fails the run before any session exists.

## Repo prerequisites

- **Create the `ready-for-agent` label** (repo → Issues → Labels): the
  dispatcher only ever considers issues carrying it. The `agent-dispatched`
  label, by contrast, is created automatically on first dispatch — the
  dispatcher creates it ahead of the session that will apply it.
- **Keep the `/label-and-implement-with-pr` skill installed on the runner
  Mac**, under `~/.claude/skills/`, along with the `/implement`, `/ui-report`,
  and `/babysit-pr` skills it calls. The dispatch prompt is just
  `/label-and-implement-with-pr issue #<N>`, so the skill is what actually
  tells the session how to work — including claiming the issue with the
  `agent-dispatched` label and opening the PR. Without it a dispatched session
  receives an unresolvable slash command.

  `/implement`, `/ui-report`, and `/babysit-pr` must **not** carry
  `disable-model-invocation: true`, unlike most of their siblings.
  `/label-and-implement-with-pr` reaches them through the Skill tool rather
  than a user prompt, which is exactly what that flag refuses; with it set,
  every dispatched session hits the refusal halfway through and falls back to
  improvising against AGENTS.md.
- **Use the `## Blocked by` convention** in issue bodies. The dispatcher parses
  `- #N` bullets under that exact heading:

  ```markdown
  ## Blocked by

  - #12
  - #15
  ```

  An issue with no such section (or an empty one) is treated as never-blocked
  and qualifies on any dispatcher run. Since the dispatcher only runs on an
  issue close or a manual re-scan, a never-blocked issue starts either the next
  time anything closes or when you run the workflow by hand.

## One-time Mac setup

1. **Register the runner**: repo → Settings → Actions → Runners → *New
   self-hosted runner* (macOS/ARM64), then install it as a service so it
   survives reboots: `./svc.sh install && ./svc.sh start`. Jobs queue for up to
   24 h while the Mac is offline/asleep.
2. **Paseo daemon at login**: make sure the Paseo daemon starts automatically
   (the desktop app's login-item setting) and that `paseo ls` works from a
   terminal. The runner looks for `paseo` on `PATH` plus `/opt/homebrew/bin`,
   `/usr/local/bin`, and `~/.local/bin`.
3. **Point at the checkout**: set the repository Actions **variable**
   `PASEO_PROJECT_DIR` to the absolute path of this repo's clone on the Mac
   (Settings → Secrets and variables → Actions → Variables). Sessions spawn
   worktrees off this clone, and the spawn step fetches it first, so its
   `origin` must be reachable unattended as the runner's user (an SSH key with
   no passphrase prompt, or a stored credential helper).
4. **`gh` and `claude` logged in**: sessions read issues with `gh` and run on
   the Claude CLI's subscription login, so both must be authenticated for the
   account the daemon runs under.

## Manual dispatch

`unblock-dispatch.yml` accepts a manual run from the Actions tab, which
re-scans the backlog under the normal scope rules. This is how never-blocked
issues get started — nothing has to close first — and how you drain a backlog
after raising the in-flight cap or fixing a `## Blocked by` list.

`agent-implement.yml` also accepts a manual run with any issue number, which
bypasses the scope rules entirely — the escape hatch for an umbrella issue or
one you haven't labeled `ready-for-agent`. It still counts against the in-flight
cap: the run holds the issue while it is live, and the session it spawns labels
the issue like any other. The spawn-time re-check still applies — a closed or
already-claimed issue needs **force** ticked — and so does the one-session
limit, which **force** does not lift.
