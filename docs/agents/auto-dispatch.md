# Auto-dispatch: ready issues to T3 Code threads

The existing `unblock-dispatch.yml` scan starts implementation after an issue
is completed or a manual rescan. It selects open `ready-for-agent` issues with
no open blockers under `## Blocked by`, skips umbrella issues and preserves
the per-repository in-flight cap, active-run guard and handoff grace period.

`agent-implement.yml` re-checks whether the issue is closed or claimed on the
Mac, then invokes `scripts/start-agent-thread.py`. The launcher checks host
capacity, fetches origin and creates an isolated T3 thread on
`agent/issue-<N>`, based on `origin/main` by default.

The `label-and-implement-with-pr` skill claims the issue with
`agent-dispatched` as its first action, implements and verifies the work,
opens a PR and supervises it. The dispatcher never claims an issue before a
session exists. A launch receipt is not implementation or test acceptance.
Giving up removes the claim with an explanation; a PR awaiting review retains it.

## Host capacity

These launchers admit at most three active automated threads across
participating projects on the same T3 server. A shared, locked project registry
queries their live thread state before admission. Checking capacity and
launching hold the same host lock, including across repository checkouts.
Projects enroll automatically on their first dispatch.

Only top-level `agent/issue-<N>` threads in preparing, queued, starting,
running or waiting states consume slots. Manual work on other branches and
idle/completed threads do not. Capacity reads or a malformed registry fail
closed. `force` overrides only the issue re-check, never host capacity.
A full host defers launch; rescan after capacity becomes available.

The registry lives in `~/.local/state/t3-agent-implement/<server-home-hash>.json`.
It stores only registered project paths; thread status is read live. Every
participating launcher on a server must use the same state path. Preserve it
across deployments. If a project is removed or moved, reconcile its registry
entry after confirming no automated work remains. Existing manually launched
Paseo sessions are independent of this T3 admission guard.

## Configuration

Set these repository Actions variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `T3_PROJECT_DIR` | yes | none | Absolute path of this repo's registered checkout on the runner |
| `T3_BASE` | no | `origin/main` | New worktree base |
| `T3_CLI` | no | PATH, then `~/.t3/bin/t3` | CLI executable |
| `T3_BASE_DIR` | no | CLI default | T3 home for a custom server |
| `T3_DISPATCH_STATE` | no | Shared registry above | One shared absolute host admission path |

Save the project's provider, model, reasoning options and permission mode in
T3 before enabling unattended dispatch. The launcher inherits that selection;
provider/model overrides would discard saved reasoning options. It creates no
project and uses no unsupported reasoning or permission CLI flags. Legacy
`PASEO_*` variables remain available for rollback but are no longer read.

## Runner setup and verification

1. Register the existing checkout as a T3 project once. Keep the T3 server
   running under the same account as the macOS self-hosted Actions runner.
2. Save the intended provider/model/options and unattended permissions.
   Authenticate that provider and `gh`; confirm origin is reachable unattended.
3. Install `label-and-implement-with-pr`, `implement`, `ui-report` and
   `babysit-pr` under the canonical `~/.agents/skills`. The project
   [T3 adapter](t3-code.md) supplies their T3 execution mechanics; Paseo
   sessions retain their own mechanics.
4. Set `T3_PROJECT_DIR` and check connectivity without launching work:

   ```sh
   ~/.t3/bin/t3 thread list --project /absolute/path/to/checkout --json
   ```

5. After the workflow reaches the default branch, dispatch it for an issue
   actually intended for implementation. Verify the T3 thread, worktree,
   issue claim, PR and native watch. Local mocked tests do not prove this
   unattended delivery path.

Investigate an uncertain CLI result before retrying: check for an existing
thread, branch and claim rather than blindly launching again. The command
returns without waiting for implementation. The workflow keeps its
`Agent implement: issue #N` run-name contract for duplicate protection.

Run `unblock-dispatch.yml` manually to rescan. An explicit issue passed to
`agent-implement.yml` bypasses automatic selection rules, while its
closed/claimed re-check remains unless `force` is selected.

On-demand actions are shared in `t3.json`. Launcher and hook tests run in
`agent-integration.yml`. Existing app CI coverage and release workflows stay
unchanged. Schedules are managed separately and move only when requested.
