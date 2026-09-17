# Auto-dispatch: ready issues to Paseo agent sessions

Issues marked `ready-for-agent` are implemented automatically after their
blockers close. Paseo starts a configured agent provider on the self-hosted Mac
runner. Sessions remain visible in the Paseo desktop and mobile apps.

## How it works

Two workflows split detection from execution:

1. `unblock-dispatch.yml` scans open `ready-for-agent` issues when an issue is
   completed or the workflow is run manually. It parses `- #N` bullets under
   `## Blocked by`, skips umbrella issues, and dispatches work that is ready.
2. `agent-implement.yml` re-checks the issue on the Mac, checks host capacity,
   validates the configured Paseo provider and model, fetches the checkout,
   and starts a background worktree session on `agent/issue-<N>`.

The instruction tells the selected agent to use the
`label-and-implement-with-pr` skill for the issue. That shared skill claims the
issue with `agent-dispatched`, uses `implement`, creates a UI report when
needed, opens a pull request, and hands the PR to `babysit-pr`.

Shared skills come from `~/.agents/skills` on the runner. Client-specific skill
locations may be compatibility adapters, but they are not the source of truth.

## Capacity and claims

The host carries at most three workflow-started sessions at once. Before
spawning, the workflow runs `paseo ls --global --json` and counts sessions with
the `agent-implement=<issue>` label whose state is `initializing` or `running`.
Manual Paseo sessions and idle sessions do not count.

The workflow requires CLI support for `ls --global` and `run --label`. It fails
closed if either feature is missing. The manual `force` input can override a
closed or already-claimed issue, but it cannot override host capacity.

The agent applies `agent-dispatched` as its first act. The dispatcher does not
apply it because a queued job is not proof that an agent started. A live spawn
run and its short handoff grace period prevent duplicate dispatches before the
agent has applied the label.

## Scope rules

- Only issues labeled `ready-for-agent` are selected automatically.
- An issue is ready when its `## Blocked by` list is empty or all listed issues
  are closed.
- Titles beginning `[Epic]` or `Spec:` are skipped.
- At most three issues are in flight across repositories using this workflow
  on the same Paseo host.
- A session that gives up removes `agent-dispatched` and comments on the issue.

## Paseo configuration

Set these repository Actions variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `PASEO_PROJECT_DIR` | yes | none | Checkout path on the runner |
| `PASEO_PROVIDER` | yes | none | Provider passed to `paseo run` |
| `PASEO_MODEL` | yes | none | Model passed to `paseo run` |
| `PASEO_THINKING` | no | unset | Optional reasoning option |
| `PASEO_MODE` | no | unset | Optional provider permission mode |
| `PASEO_BASE` | no | `origin/main` | Ref used to create the worktree branch |

There are deliberately no provider, model, thinking, or permission-mode
defaults. Unattended automation must make those choices explicitly. Interactive
client preferences remain separate.

Before fetching or starting an agent, the workflow:

1. confirms `paseo` and `PASEO_PROJECT_DIR` exist;
2. checks `paseo provider ls --json` for an available provider;
3. runs `paseo provider diagnostic <provider>` to confirm authentication;
4. checks the model and optional thinking value against
   `paseo provider models <provider> --thinking --json`.

Any failure stops before branch or session creation and prints an actionable
Actions error. Inspect available values with:

```sh
paseo provider ls
paseo provider models <provider> --thinking
paseo provider diagnostic <provider>
```

The workflow fetches the checkout before invoking:

```sh
paseo run --background \
  --provider <provider> \
  --model <model> \
  --cwd <checkout> \
  --new-workspace worktree \
  --worktree-mode branch-off \
  --new-branch agent/issue-<N> \
  --base origin/main \
  --label agent-implement=<N> \
  "Use the label-and-implement-with-pr skill to implement issue #<N>."
```

Optional `--thinking` and `--mode` arguments are added only when their variables
are set. An alternate `PASEO_BASE`, such as `origin/release`, must resolve in
the runner checkout.

## Repository prerequisites

- Create the `ready-for-agent` label. The workflows create
  `agent-dispatched` if needed.
- Keep `label-and-implement-with-pr`, `implement`, `ui-report`, and
  `babysit-pr` current under `~/.agents/skills` on the runner.
- Use the exact `## Blocked by` heading and `- #N` bullets when declaring
  dependencies.

## One-time Mac setup

1. Register a macOS self-hosted runner and install it as a service.
2. Start the Paseo daemon at login and confirm `paseo ls` works for the runner
   account.
3. Set `PASEO_PROJECT_DIR`, `PASEO_PROVIDER`, and `PASEO_MODEL` in repository
   Actions variables. Ensure the checkout's `origin` is reachable unattended.
4. Authenticate `gh` and the selected Paseo provider for the same account.

## Manual dispatch

Run `unblock-dispatch.yml` manually to rescan the eligible backlog. Run
`agent-implement.yml` with an issue number to bypass the automatic scope rules.
The spawn-time re-check and host capacity limit still apply; `force` only
overrides the issue-state checks.
