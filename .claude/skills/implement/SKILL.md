---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

First, if the work is a GitHub issue, add the `agent-dispatched` label: `gh issue edit <number> --add-label "agent-dispatched"`.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Always finish by committing your work to the current branch, pushing the branch,
and opening a pull request (`gh pr create`) — every time, without asking. The
PR title must follow Conventional Commits, and the body should list the
acceptance criteria and how they were verified. This is the default close-out
for every `/implement` run; do not stop at a local commit.
