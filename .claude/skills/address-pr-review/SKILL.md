---
name: address-pr-review
description: Work through pull-request review feedback end-to-end on GitHub — gather every comment (inline line comments, review summaries, and conversation comments), investigate each one, fix the code or push back with reasoning, verify, then commit, push, and reply-and-resolve the threads. Use this whenever the user wants to address reviewer feedback, respond to PR comments, "fix the comments on PR #N", resolve review threads, or work through a code review — even when they just say "handle the review" or "the reviewer left some notes". GitHub PRs via the gh CLI.
---

# Address a PR review

A review is a conversation, not a checklist. The reviewer flagged things they want changed or explained; your job is to treat each one honestly — fix what's right, push back on what isn't — and leave the PR in a state where the reviewer can see exactly what happened to every comment they wrote.

Work through five phases in order. Don't skip the gathering or the investigation: the most common failure mode is fixing comments blindly or missing half of them.

## Phase 1 — Gather every piece of feedback

GitHub scatters review feedback across **three separate surfaces**, and they don't overlap. Pull all three, because relying on one misses the rest:

1. **Inline review comments** — anchored to specific lines/diff hunks. This is usually where the substance is.
2. **Review summaries** — the top-level body a reviewer writes when they submit "Request changes" / "Approve" / "Comment".
3. **Conversation comments** — general PR discussion not tied to a line.

A frequent trap: `gh pr view <n> --comments` only shows the conversation surface and **silently omits inline review comments**. If you stop there you'll think there's no feedback when there are a dozen line comments. Always hit the REST API for the inline comments.

The exact commands (and how to handle the large JSON payloads) are in `references/github-pr-api.md`. Read it now.

When the payload is large, don't dump raw JSON into your context. Extract just what you need per comment: **file path, line, the comment body, the comment id** (you'll need it to reply), and the **diff hunk** (for context on what the reviewer was looking at). A small script that prints one tidy block per comment beats scrolling 40KB of JSON.

## Phase 2 — Investigate each comment before touching code

This is the phase people skip, and it's the one that matters most. A reviewer's comment is a *claim*, and claims can be wrong, outdated, or based on a misread of the diff. Treat each one as something to verify, not an order to obey.

For every comment, read the actual code it points at and confirm the premise holds. Check the relevant docs, library types, or config when a comment makes a factual assertion ("this is a version regression", "this prop defaults to X", "this file is unused"). It's cheap to verify and expensive to ship a "fix" that breaks something that was fine.

Two real examples of why this pays off:
- A reviewer flagged a dependency version as a "36-major-version regression." Checking the SDK's bundled-modules manifest showed the new version was the *correct* pinned one — the old version was the mistake. The right move was to leave it and explain, not to "fix" it back to broken.
- A reviewer worried two comments contradicted each other about whether a wrapper component blocked touches. Reading the library's type definitions resolved it: the prop defaulted to off and only drove a visual effect, so neither concern applied. Knowing that changed the fix.

Sort each comment into one of:
- **Valid → fix it.** The comment is right; change the code.
- **Wrong or not applicable → push back.** Don't change the code. You'll reply with your reasoning in Phase 5 and leave the thread open for the reviewer to weigh in — resolving a thread you disagreed with is presumptuous.
- **Needs the user's call.** Genuinely ambiguous, or a judgment call about product/scope. Surface it to the user rather than guessing.

Watch for comments that share a root cause. Often a "simplify this" note makes a whole branch of other comments moot — e.g. removing a now-unnecessary code path can erase three separate "nested-this" and "fix-that" comments at once. Solve the root, not each leaf.

## Phase 3 — Make the changes and verify

Apply the fixes for the valid comments. Keep the changes scoped to what the review asked for — a review response is not the time for unrelated refactors.

Then verify with the repo's own checks before you even think about committing: typecheck, lint, and tests as available (e.g. `tsc --noEmit`, the project lint script, the test runner). Distinguish pre-existing warnings from anything your change introduced, so you can say so honestly. Shipping a review fix that breaks the build is worse than the original comment.

## Phase 4 — Commit and push (confirm first)

Bundle the whole review response into **one commit** — a single, coherent "address review feedback" change is easier to read than a commit per comment.

Committing and pushing touch shared state, so **confirm before both**. Show the user:
- a short summary of what you changed and what you pushed back on,
- the diff (or a tight diff stat for large ones),
- the proposed commit message.

Wait for the go-ahead. Approval to commit is also approval to push unless they say otherwise. Write the message focused on *why* (addressing review), reference the PR, and follow the repo's commit conventions. Never use `--no-verify` or skip hooks to force it through — if a hook fails, fix the cause.

## Phase 5 — Reply to and resolve the threads

Now close the loop on GitHub so the reviewer sees the disposition of every comment. This is the step that turns "I made some changes" into "your review was addressed."

For each thread:
- **Fixed in code:** reply with a one-line note on what changed (referencing the pushed commit is nice), then resolve the thread.
- **Pushed back:** reply explaining your reasoning, and **leave the thread open** — the reviewer decides whether they're satisfied.
- **Deferred to the user:** leave it for them.

Replying and resolving use two different GitHub APIs with two different IDs — the REST comment id (for replies) and the GraphQL thread node id (for resolving), and you correlate them via the comment's `databaseId`. This is the most error-prone part of the whole flow; the exact queries and the correlation trick are in `references/github-pr-api.md`. Read it before you start posting.

Keep replies short and specific. "Done — switched to theme-aware colors in `index.tsx`/`trips.tsx`" is better than a paragraph. The reviewer can read the diff; the reply just tells them where to look and that you heard them.

## Prerequisites

`gh` authenticated with the `repo` scope (needed both to post replies and to run the `resolveReviewThread` GraphQL mutation). Check with `gh auth status`.
