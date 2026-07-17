# Auto-dispatch: unblocked issues → Paseo agent sessions

When a PR merges and closes an issue that was blocking other issues, the newly
unblocked issues get implemented automatically: a fresh Claude Code session is
spawned for each one via [Paseo](https://paseo.sh) on a self-hosted Mac runner.
Sessions run on the Mac's Claude subscription login (no API credits) and are
visible in the Paseo desktop/mobile apps.

## How it works

Two workflows split detection from execution:

1. **`unblock-dispatch.yml`** (GitHub-hosted, pure scripting) runs on every
   `issues: closed` event where the issue was closed as *completed*. It scans
   open `ready-for-agent` issues, parses each body's `## Blocked by` section
   (`- #N` bullets), and keeps issues whose blockers are now all closed. For
   each, it applies the `agent-dispatched` label (the idempotency guard) and
   fires `agent-implement.yml` with the issue number.
2. **`agent-implement.yml`** (self-hosted Mac runner) runs
   `paseo run --detach --model claude-opus-4-8 --thinking high --worktree
   claude/issue-<N> "/implement issue #<N>"` — the repo's `/implement` skill
   carries the full workflow instructions. `--detach` means the session runs
   under the Paseo daemon and outlives the (short) runner job; `--worktree`
   keeps parallel sessions from clobbering one checkout.

   Model and reasoning effort are **pinned to Opus 4.8 at high effort** rather
   than left to the daemon's defaults, which move as new models ship. Change
   them in one place: the `paseo run` flags in `agent-implement.yml`. Valid
   values come from `paseo` itself — the model IDs and `--thinking` options the
   Claude provider accepts are listed by the daemon (`claude/opus`-family IDs
   like `claude-opus-4-8`, efforts `low`/`medium`/`high`/`xhigh`/`max`).

### Scope rules

- Only issues labeled `ready-for-agent` are dispatched.
- Only issues that were **actually blocked** (at least one `- #N` bullet under
  `## Blocked by`) qualify — never-blocked issues are started manually, and
  epics (`[Epic]` title prefix) are always skipped.
- At most **3** issues carry the `agent-dispatched` label at once. Unblocked
  issues beyond the cap are deferred; because every dispatcher run re-scans all
  formerly-blocked open issues, they're picked up automatically the next time
  any issue closes.
- If a session gives up, it removes the issue's `agent-dispatched` label and
  comments — which frees a slot and makes the issue eligible again.

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

`agent-implement.yml` also accepts a manual run from the Actions tab with any
issue number — handy for kicking off a never-blocked issue through the same
pipeline. Add the `agent-dispatched` label yourself if you want it counted
against the in-flight cap.
