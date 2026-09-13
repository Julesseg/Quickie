---
name: babysit-pr
description: "Babysit an open pull request until it merges: watch CI, review comments, and mergeability; fix branch-caused CI failures, act on review feedback, rebase when the branch conflicts with or falls behind its base, rerun flaky checks. Use right after opening a PR, or when asked to watch, monitor, or babysit one."
---

# Babysit a pull request

Watch the PR until it is merged or closed, fixing what blocks it as it
happens. Nobody is reading the session: anything you would ask in chat goes
on the PR as a comment instead, and the loop keeps running while the answer
is pending.

The PR is the argument (number or URL) or, without one, the PR for the
current branch. Work on its head branch only, from a clean tree.

## The loop

Run the watcher, act on what it surfaces, run it again. One watcher per PR;
launch it in the background (the Bash tool's `run_in_background`) so the
turn ends while nothing happens and resumes the moment something does:

```sh
python3 <this skill's dir>/scripts/gh_pr_watch.py --pr <n> --watch --until-change --max-wait 1800
```

It streams one JSON line per poll and exits on the first snapshot that needs
action, on any change of state, or when `--max-wait` runs out (`event:
timeout`, meaning nothing happened: launch it again). A foreground run must
keep `--max-wait` under 540 seconds, the Bash tool's ceiling. The last
`snapshot` line's `actions` list is your work, in this order:

1. `process_review_comment`: see Review feedback.
2. `rebase_onto_base`: see Rebase.
3. `diagnose_ci_failure`, `retry_failed_checks`: see CI.
4. `idle`, `ready_to_merge`: nothing to do. Relaunch.
5. `stop_pr_closed`, `stop_exhausted_retries`, `stop_budget_spent`: see Stop.

Feedback comes before CI because a fix commit re-triggers CI anyway, and a
rerun on a SHA about to be replaced is wasted. A push ends nothing: relaunch
the watcher in the same turn, on the new SHA. The loop's completion
criterion is a stop action, never a quiet snapshot.

## Review feedback

Every surfaced item is a claim. Read the code it points at and check the
premise before changing anything, then sort it:

- **Valid**: fix it, commit (`fix: address review feedback on #<n>`), push,
  reply on the thread with what changed and the commit, resolve the thread.
- **Wrong or not applicable**: reply with the reasoning and leave the thread
  open; the reviewer closes it.
- **A question, or a call only the reviewer can make**: reply asking exactly
  what you need. The answer arrives as a new comment and the loop picks it up.
- Approvals, acknowledgements, and your own earlier replies: nothing to do.

Every reply starts with `[agent]`. Comments that share a root cause get one
fix and a reply each. Reply and resolve mechanics, and which endpoint holds
which kind of comment: `references/github-api-notes.md`.

## Rebase

`rebase_onto_base` means the branch conflicts with its base (`DIRTY`) or sits
behind it (`BEHIND`), which blocks merging under up-to-date branch
protection. The snapshot's `pr.base_branch` names the base:

```sh
git fetch origin <base> && git rebase origin/<base>
```

Conflicts: the resolving-merge-conflicts skill. Then run the project's fast
checks (the local loop AGENTS.md names), push with `--force-with-lease`, and
let CI verify the rest. Rebase rather than merge, so the branch stays linear.

## CI

Classify first, with `references/heuristics.md`. Fetch a failed job's log as
soon as that job fails (`failed_jobs[].logs_endpoint`) rather than waiting
for the whole run.

- **Branch-caused** (the failure is in code the PR touched): fix, commit
  (`fix: <what broke>`), push.
- **Flaky or infrastructure**: rerun with `--retry-failed-now` when the
  watcher offers `retry_failed_checks`; the budget is 3 reruns per SHA.
  Unrelated tests, CI config, and dependency pins stay as they are.
- **Ambiguous**: one pass through the logs, then pick one of the above.

## Stop

Stop only on a stop action or a blocker:

- `stop_pr_closed`: the PR merged or closed. Done.
- `stop_exhausted_retries`, or any blocker only a human can clear (push
  rejected, `gh` auth failing, unrelated uncommitted changes in the tree, a
  reviewer request that needs a product decision): post one comment on the
  PR, `[agent] Needs a human: <what and why>`, then stop.
- `stop_budget_spent`: the watch has run for `--budget-seconds` (default
  24 h). Post `[agent] Stopped watching after <n> h; run babysit-pr again to
  resume.` and stop.

A green, mergeable, review-clean PR is a milestone, not a stop: approval and
merging belong to the reviewer, so relaunch the watcher.

## Guardrails

- Commit named files, with hooks running (no `--no-verify`).
- Force-push only right after a rebase, with `--force-with-lease`.
- The PR's own state (draft, ready, open, closed, merged) and threads other
  people hold between themselves are theirs to change. You post replies and
  resolve the threads you fixed.

## Report

When you stop, say: final SHA, CI state, mergeability, commits pushed,
reruns used, and what is still open.
