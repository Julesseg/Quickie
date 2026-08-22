---
name: label-and-implement-with-pr
description: "Implement a GitHub issue end to end for auto-dispatch: claim it with the agent-dispatched label, run the implement skill, then open a pull request."
disable-model-invocation: true
---

Implement the GitHub issue the user named, as a dispatched agent session. This
is the entry point the auto-dispatch pipeline invokes. It wraps the implement
skill in the two things a dispatched session owes the pipeline: a claim at the
start and a pull request at the end.

## 1. Claim the issue, before anything else

```sh
gh issue edit <number> --add-label "agent-dispatched"
```

This session is the only thing that applies that label. The dispatcher
deliberately does not, so the label always means a session really started and
never that one was merely asked for. Claim the issue first, before any other
work: until you do, the dispatcher is holding the issue on a grace period that
runs out.

If the label does not exist yet, create it and retry: `gh label create
agent-dispatched --color 1d76db --description "An agent session has been
dispatched for this issue"`.

If you give up on the issue, remove the label and comment saying why. That
hands the issue back to the dispatcher and frees an in-flight slot.

## 2. Do the work

Call the Skill tool with "implement", passing the issue as the work to build.
That skill owns how the work gets built: TDD at pre-agreed seams, regular
typechecking and single test files, the full suite once at the end, and a
code review before committing. Do not restate or second-guess it here.

## 3. Open a pull request

The implement skill leaves the work committed on the current branch. Take it
from there.

**Bring the base branch in before opening the PR**: `git fetch origin main`
and merge (or rebase onto) `origin/main`, resolving any conflicts and
re-running the full test suite afterwards. Do this even if the branch was
current when the session started, because other agents merge while you work.

A pull request that conflicts with its base gets **no CI checks at all**:
GitHub cannot build the merge commit, so it never creates them, and the PR
looks identical to one whose CI has not started yet. Left alone it stalls
unnoticed. Conflicts found here are also far cheaper to resolve, while you
still have the context that produced the code.

Then push the branch and open the pull request (`gh pr create`), every time,
without asking. The title must follow Conventional Commits. The body must
close the issue (`Closes #<number>`) and list the acceptance criteria with how
each one was verified. This is the close-out for every run: do not stop at a
local commit.
