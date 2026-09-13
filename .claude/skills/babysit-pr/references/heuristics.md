# CI and review heuristics

## CI classification

**Branch-caused**: the logs tie the failure to the PR branch.

- Compile, typecheck, or lint failures in files the branch touched
- Deterministic test failures in changed areas
- Snapshot or screenshot diffs caused by UI or text changes in the branch
- Static-analysis findings introduced by the latest push
- A build script or CI config change in the PR causing a deterministic failure

**Flaky or unrelated**: the logs point at something transient or external.

- DNS, network, or registry timeouts while fetching dependencies
- Runner provisioning or startup failures, GitHub Actions service incidents
- Rate limits or transient outages of an external service
- A simulator that timed out booting ("Timed out waiting for AX loaded
  notification", "Timed out while requesting launch progress")
- Non-deterministic failures in tests the branch did not touch

Flaky or unrelated failures get a rerun from the retry budget, never a code
change: tests the branch did not touch, build scripts, CI configuration,
dependency pins, and infrastructure code stay as they are.

Uncertain: read the failed job's log once, then decide.

## Decision tree

1. PR merged or closed: stop.
2. Failed checks:
   - Diagnose first. A job that already failed while the run is still
     pending has its log available now; read it now.
   - Branch-caused: fix locally, commit, push.
   - Flaky or unrelated and every check for this SHA is terminal: rerun
     the failed jobs.
   - Flaky or unrelated and not rerunnable: post the blocker on the PR and
     stop.
   - Still pending with no failed job yet: wait.
3. Reruns on this SHA have hit the limit (default 3): post the persistent
   failure on the PR and stop.
4. Independently of CI: act on every new review item.

## Review agreement

Fix a comment in code when it is technically right, actionable on this
branch, consistent with the issue's intent, and doable without unrelated
refactors.

Reply instead of fixing when the comment is ambiguous, contradicts the
issue, needs a product or design decision, or asks a question. The reply
states what is needed; the loop keeps watching for the answer.

## Blockers that need a human

- Unrelated uncommitted changes in the worktree
- `gh` auth or permission failures
- A push the remote rejects
- CI still failing after the rerun budget
- A reviewer request that needs a decision only they can make
