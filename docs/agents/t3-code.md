# T3 Code orchestration

Apply this adapter inside T3 Code. Sessions launched by Paseo retain their
Paseo orchestration and shared skills. The execution mechanics below take
precedence over Paseo commands in shared skills when running inside T3.

## Project and worktrees

Reuse this registered project. Independent changes use isolated worktrees
based on the current remote default branch. Helpers run in the current
thread's checkout; a separate checkout is not a new registered project.
Preserve unrelated local edits and existing provider configuration.

Import the on-demand actions from `t3.json` in Settings → Projects on another
environment. Core tests run without a simulator. The generic simulator build
action builds the app without booting a device. These are local checks;
canonical UI acceptance remains the repository's existing CI contract.

## Shared workflows

| Shared workflow | T3 execution |
| --- | --- |
| `paseo-advisor` | One read-only child with a self-contained question and recommendation request. |
| `paseo-committee` | Two independent read-only children; collect findings and resolve objections. |
| `code-review` | Separate Standards and Spec children, given the fixed diff and relevant sources. |
| `paseo-handoff` | A self-contained child task; create a top-level thread only if the user requests a new thread. |
| `paseo-loop` | Bounded unscheduled worker/verifier cycles using task completions. |
| `babysit-pr` | The top-level thread uses native PR watches, as described below. |
| `label-and-implement-with-pr` | Claim, implement, verify, open and link the PR; the top-level thread supervises it. |

Verify the selected provider and settings before launching a child. Every
child uses the original top-level provider, including nested work, unless
the user explicitly requests another provider. Paseo profile names are not
T3 model identifiers: use a role brief and available provider/model/options.

Use native children for the same provider, an offered model and inherited
settings. Use `delegate_task` for requested settings, a separate worktree or
background agent work. Discover capabilities before the first delegation.
Follow completion notifications and the tool's `next`; cancel replaced or
unneeded tasks. Every new review or re-check is a fresh task. Children create
no further children unless their brief requests them.

A handoff includes the objective, branch/head, uncommitted work, decisions,
unsuccessful attempts, acceptance criteria, verification, blockers and PR
links. Use the returned link when referring to another T3 thread.

Unscheduled worker/verifier cycles have explicit exit criteria, iteration
and elapsed-time limits. Each verifier receives the changed head and original
criteria. Report unresolved failures at the limit. Schedules are configured
separately: keep them on their current host unless the user requests moving
them, and avoid duplicate scheduled execution.

## Pull requests

Keep the `babysit-pr` skill's review, rebase and CI classification policies.
Replace its managed-terminal watcher lifecycle with T3 native PR watches:

1. Verify the PR scope and current head, and handle existing feedback first.
2. After creating, taking over or pushing to a PR, immediately call
   `link_pull_request` with the full URL, including every stack layer.
3. The top-level thread calls `watch_pull_request` after any required update
   and push, then ends its turn. A child returns the PR URL, head SHA and
   check/review state; its parent owns the watch.
4. On a wake, read the current head, reviews, checks and base. Handle feedback
   before CI retries. Diagnose first and preserve the existing bounded retry
   policy; use a narrower project limit where one exists. Native watches
   remain active across pushes and wakes.
5. Before final handback or a human blocker, call `unwatch_pull_request` and
   report the head, CI/review state and remaining work. Deliberately waiting
   for the next native watch event is not a handback.

Passed required checks do not establish complete UI coverage or authorize
merging. Preserve successful evidence when retrying an infrastructure failure.
Stop, settlement and archival can end watches. Comments from the GitHub account
T3 uses do not wake its watch; surface owner decisions in the T3 thread and
explicitly hand back. Use native watches instead of terminal polling or
scheduled PR reminders.

## Devices and hooks

Record already-booted simulators and leave them alone. For interactive checks,
use `device_list`, `device_open` and its returned `agent-device` CLI; inspect
with `device_screenshot`. Builds, installs, logs and the project's test runners
may use Xcode/simctl. Closing the Device panel leaves the simulator running:
shut down devices this task booted, including after failures, and quit
Simulator only when none remain booted.

Keep the existing Claude, Codex and Pi adapters. Codex maps `exec_command`
to `Bash` with `tool_input.command` in hook payloads, so its `^Bash$` matcher
is intentional. Hook trust/loading belongs to the provider, not project actions.

## References

- [Host CLI](https://github.com/pingdotgg/t3code/blob/main/docs/user/outside-agents.md#scripts-on-the-host)
- [PR watches](https://github.com/pingdotgg/t3code/blob/main/docs/user/source-control.md#linked-pull-requests)
- [Project actions](https://github.com/pingdotgg/t3code/blob/main/docs/user/project-settings.md)
- [Devices](https://github.com/pingdotgg/t3code/blob/main/docs/user/devices.md)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks#tool-coverage)
