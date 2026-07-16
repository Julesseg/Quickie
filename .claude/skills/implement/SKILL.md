---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

First, if the work is a GitHub issue, claim it: `gh issue edit <number> --add-label "agent-dispatched"`. The label marks an agent session as in flight on the issue (it counts against the auto-dispatch in-flight cap — see `docs/agents/auto-dispatch.md`). It may already be present when the session was spawned by the dispatcher; that's fine, adding it is idempotent. If you give up on the issue, remove the label and comment on the issue explaining what's missing.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch.
