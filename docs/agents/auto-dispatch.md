# Auto-dispatch: unblocked issues → T3 Code agent sessions

When a PR merges and closes an issue, any `ready-for-agent` issue with no open
blockers — newly unblocked or never blocked — gets implemented automatically: a
fresh Claude Code session is spawned for each one in
[T3 Code](https://t3.chat/code) on a self-hosted Mac runner.
Sessions run on the Mac's Claude subscription login (no API credits) and are
visible in the T3 Code app like any session you started by hand.

## How it works

Two workflows split detection from execution:

1. **`unblock-dispatch.yml`** (GitHub-hosted, pure scripting) runs on every
   `issues: closed` event where the issue was closed as *completed* (and on
   manual `workflow_dispatch`, which performs the same scan). It scans open
   `ready-for-agent` issues, parses each body's `## Blocked by` section
   (`- #N` bullets), and keeps issues whose blockers are all closed —
   including issues that never had blockers. For each, it applies the
   `agent-dispatched` label (the idempotency guard) and fires
   `agent-implement.yml` with the issue number.
2. **`agent-implement.yml`** (self-hosted Mac runner) starts a session in the
   T3 Code app running on that Mac: it cuts a `claude/issue-<N>` worktree off
   `origin`'s default branch, creates a thread on it, and sends
   `/implement issue #<N>` — the repo's `/implement` skill carries the full
   workflow instructions. The session belongs to the app rather than to the
   job, so it outlives the (short) runner job; the per-issue worktree keeps
   parallel sessions from clobbering one checkout.

   There is no T3 Code CLI equivalent of `paseo run`, so the step drives the
   app's local HTTP API (`POST /api/orchestration/dispatch`) directly. It mints
   its own credential per run with `t3 auth session issue --token-only`, which
   signs a short-lived bearer token against the state directory the app owns —
   so nothing long-lived has to be stored in a repo secret. The app writes its
   address to `~/.t3/userdata/server-runtime.json` on startup; the step reads it
   there and fails red if nothing is listening.

   Sessions run on **Opus 4.8 at high reasoning effort, in full-access mode**
   by default, pinned rather than inherited from the app. All three are
   overridable — see [Model, reasoning effort, and runtime
   mode](#model-reasoning-effort-and-runtime-mode).

### Scope rules

- Only issues labeled `ready-for-agent` are dispatched.
- Any such issue with **no open blockers** qualifies — whether its
  `## Blocked by` list (`- #N` bullets) is now fully closed or it never had
  blockers at all. Epics (`[Epic]` title prefix) are always skipped.
- Each run spawns at most **2** new sessions, and at most **3** issues carry
  the `agent-dispatched` label at once. Startable issues beyond either cap are
  deferred; because every dispatcher run re-scans all open ready issues,
  they're picked up automatically the next time any issue closes (or the
  dispatcher is run manually).
- If a session gives up, it removes the issue's `agent-dispatched` label and
  comments — which frees a slot and makes the issue eligible again.

### Model, reasoning effort, and runtime mode

Sessions default to **Opus 4.8 at high reasoning effort, in full-access mode**.
Three optional repository Actions variables override that without touching the
workflow (Settings → Secrets and variables → Actions → Variables):

| Variable         | Default           | Sets                        |
| ---------------- | ----------------- | --------------------------- |
| `PASEO_MODEL`    | `claude-opus-4-8` | the thread's model          |
| `PASEO_THINKING` | `high`            | the model's `effort` option |
| `PASEO_MODE`     | `full-access`     | the thread's runtime mode   |

The names still say `PASEO_` on purpose: they carried over unchanged from the
Paseo pipeline, so an already-configured repo needs no re-configuring.
Leave a variable unset (or set it empty) to fall back to the default — unlike
`PASEO_PROJECT_DIR`, none of the three are required. The defaults are pinned in
the workflow rather than inherited from T3 Code, whose own defaults move as new
models ship.

Runtime modes are `full-access`, `auto`, `auto-accept-edits`, and
`approval-required`; the workflow also accepts the Paseo spellings
`bypassPermissions`, `acceptEdits`, and `default` and maps them onto the first,
third, and fourth. Anything else fails the run with the list of valid values.
`full-access` is the default because nobody is around to answer a permission
prompt in a CI-spawned session — an approval-gated mode would stall it on its
first tool use.

**The model and the effort cannot be checked before dispatching.** Paseo's
`provider models claude --json` has no equivalent on T3 Code's HTTP API: the
model catalog only travels over the app's WebSocket channel, and dispatching
with a bad model is accepted rather than rejected. So the spawn step watches the
session for two minutes afterwards instead, and fails red with the provider's
own error if it never comes up — which is what a typo'd `PASEO_MODEL` looks
like. A session that is merely slow to start leaves a warning rather than a
failure; if it never comes up at all, the `agent-dispatched` label the
dispatcher applied keeps holding the slot until you remove it by hand.

## One-time Mac setup

1. **Register the runner**: repo → Settings → Actions → Runners → *New
   self-hosted runner* (macOS/ARM64), then install it as a service so it
   survives reboots: `./svc.sh install && ./svc.sh start`. Jobs queue for up to
   24 h while the Mac is offline/asleep.
2. **T3 Code running at login**: T3 Code is a desktop app, not a daemon, so the
   Mac has to be logged into its GUI with the app open — a locked screen is
   fine, a logged-out one is not. Set it as a login item, and check
   `~/.t3/userdata/server-runtime.json` exists and its `origin` answers
   `/api/health`. Set `T3CODE_HOME` for the runner if the app uses a data
   directory other than `~/.t3`.
3. **The `t3` CLI**: the spawn step mints its credential with it. `npm i -g t3`
   makes it a no-op; otherwise the step falls back to `npx -y t3@<version>`,
   which needs Node on the runner's `PATH` and downloads the package on a cold
   npm cache. The runner looks on `PATH` plus `/opt/homebrew/bin`,
   `/usr/local/bin`, and `~/.local/bin`.
4. **Point at the checkout**: set the repository Actions **variable**
   `PASEO_PROJECT_DIR` to the absolute path of the Quickie clone on the Mac
   (Settings → Secrets and variables → Actions → Variables). Sessions spawn
   worktrees off this clone, under `~/.t3/worktrees/<repo>/`. The workflow
   registers the clone as a T3 Code project on first dispatch if it is not one
   already.
5. **`gh` and `claude` logged in**: sessions read issues with `gh` and run on
   the Claude CLI's subscription login, so both must be authenticated for the
   account running T3 Code.

The `agent-dispatched` label is created automatically on first dispatch.

## Manual dispatch

`unblock-dispatch.yml` can be run manually from the Actions tab to scan and
dispatch startable issues without waiting for a close event — handy right after
labeling new issues `ready-for-agent`.

`agent-implement.yml` also accepts a manual run from the Actions tab with any
issue number — handy for forcing a specific issue through the pipeline out of
order. Add the `agent-dispatched` label yourself if you want it counted
against the in-flight cap.
