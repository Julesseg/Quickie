# Auto-dispatch: unblocked issues → Paseo agent sessions

When a PR merges and closes an issue, any `ready-for-agent` issue with no open
blockers — newly unblocked or never blocked — gets implemented automatically: a
fresh Claude Code session is spawned for each one via [Paseo](https://paseo.sh)
on a self-hosted Mac runner.
Sessions run on the Mac's Claude subscription login (no API credits) and are
visible in the Paseo desktop/mobile apps.

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
2. **`agent-implement.yml`** (self-hosted Mac runner) runs
   `paseo run --detach --model <model> --thinking <effort> --worktree
   claude/issue-<N> "/implement issue #<N>"` — the repo's `/implement` skill
   carries the full workflow instructions. `--detach` means the session runs
   under the Paseo daemon and outlives the (short) runner job; `--worktree`
   keeps parallel sessions from clobbering one checkout.

   Sessions run on **Opus 4.8 at high reasoning effort** by default, pinned
   rather than inherited from the daemon. Both are overridable — see
   [Model and reasoning effort](#model-and-reasoning-effort).

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

### Model and reasoning effort

Sessions default to **Opus 4.8 at high reasoning effort**. Two optional
repository Actions variables override that without touching the workflow
(Settings → Secrets and variables → Actions → Variables):

| Variable         | Default           | Passed as    |
| ---------------- | ----------------- | ------------ |
| `PASEO_MODEL`    | `claude-opus-4-8` | `--model`    |
| `PASEO_THINKING` | `high`            | `--thinking` |

Leave a variable unset (or set it empty) to fall back to the default — unlike
`PASEO_PROJECT_DIR`, neither is required. The defaults are pinned in the
workflow rather than inherited from the Paseo daemon, whose own defaults move
as new models ship.

See the current legal values with `paseo provider models claude` (efforts are
per-model, currently `low`/`medium`/`high`/`xhigh`/`max`/`ultracode` on the
Opus and Sonnet lines).

**The workflow validates both before spawning**, because `paseo run` itself
does not: given an unknown `--model` it creates the session anyway rather than
erroring, which would leave a typo'd variable silently running every issue on
the wrong model. So the spawn step checks the pair against
`paseo provider models claude --json` first and fails red — listing the valid
values — instead of dispatching.

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
   `PASEO_PROJECT_DIR` to the absolute path of the Quickie clone on the Mac
   (Settings → Secrets and variables → Actions → Variables). Sessions spawn
   worktrees off this clone.
4. **`gh` and `claude` logged in**: sessions read issues with `gh` and run on
   the Claude CLI's subscription login, so both must be authenticated for the
   account the daemon runs under.

The `agent-dispatched` label is created automatically on first dispatch.

## Manual dispatch

`unblock-dispatch.yml` can be run manually from the Actions tab to scan and
dispatch startable issues without waiting for a close event — handy right after
labeling new issues `ready-for-agent`.

`agent-implement.yml` also accepts a manual run from the Actions tab with any
issue number — handy for forcing a specific issue through the pipeline out of
order. Add the `agent-dispatched` label yourself if you want it counted
against the in-flight cap.
