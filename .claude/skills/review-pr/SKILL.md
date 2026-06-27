---
name: review-pr
description: Review a GitHub pull request and post the findings back onto the PR as comments. Takes a PR number (or lists open PRs if none is given), pulls the diff via the gh CLI, reviews it for correctness, conventions, performance, tests, and security, then submits a single PR review with inline line comments plus an overall summary. Use this whenever the user wants to review a PR, leave review comments, comment on a pull request, give feedback on a PR, or "review and comment on #1234" — especially when they want the feedback to land on GitHub rather than just printed to the terminal.
---

# Review a PR and post the findings

The built-in `/review` prints a review to the terminal and stops there. This skill goes one step further: it leaves the findings **on the PR itself** as a GitHub review, so the author sees each point next to the line it's about.

## What you're producing

A single GitHub *review* (not a pile of loose comments) that contains:

- **Inline comments** — each substantive finding anchored to the exact file and line it concerns, so the author can read the critique in context and reply or resolve it.
- **A summary body** — an overview of what the PR does and the cross-cutting points that don't belong on any one line (architecture, missing tests, overall risk).

Posting it as one review keeps the PR timeline clean and lets the author treat your feedback as a unit instead of a scattering of notifications.

## Workflow

### 1. Resolve which PR

If the user gave a PR number, use it. If they didn't, run `gh pr list` and ask which one — don't guess. If they gave a URL, the trailing number is the PR.

### 2. Gather the context

```bash
gh pr view <number> --json title,body,author,baseRefName,headRefName,state,additions,deletions,changedFiles,labels
gh pr diff <number>
```

Read the diff carefully. As you read, note the **file path and the new-file line number** for anything you'll comment on — you need both to anchor an inline comment. The line number is the line as it appears in the head version of the file (the `+`/context side of the diff), which is what GitHub calls the `RIGHT` side.

For anything beyond a small diff, read the full changed files (not just the hunks) so you understand the surrounding code before critiquing it. A finding that ignores the function it lives in is usually wrong.

### 3. Review the changes

Review for the things that actually bite people, roughly in priority order:

- **Correctness** — logic errors, off-by-ones, unhandled cases, race conditions, broken error handling. This is where most of the value is.
- **Project conventions** — does it match how the rest of this codebase does things? Check neighboring files if unsure.
- **Performance** — only where it matters (hot paths, N+1 queries, unbounded growth). Don't micro-optimize.
- **Test coverage** — are the new code paths tested? Are the tests meaningful or just present?
- **Security** — injection, auth gaps, secrets in code, unsafe deserialization, missing input validation.

Be concrete. "This could be cleaner" helps no one; "this loses the original error — wrap it with `%w` so callers can still match on it" does. Every inline comment should be something the author can act on.

Don't pad the review. If the PR is clean, say so and post a short, positive summary with few or no inline comments. A review that invents nitpicks to look thorough trains people to ignore you.

### 4. Decide what goes inline vs. in the summary

- A finding tied to a **specific changed line** → inline comment at that `path` + `line`.
- A finding about the PR **as a whole**, or about something *missing* (a test that isn't there, a config that wasn't updated) → the summary body, since there's no line to anchor to.

Inline comments **must** point at a line that appears in the diff. GitHub rejects the entire review if even one anchor is off, so when in doubt about whether a line is in the diff, put the point in the summary instead.

### 5. Show the user, then post

Posting writes to a PR the whole team can see, so show your draft first — the summary plus the list of inline comments and where they'll land — and post only after the user confirms. (If they already said something like "review and post it" or "just post the comments," take that as confirmation and skip the extra round-trip.)

To post, write the findings to a JSON file and hand it to the bundled script:

```bash
python3 <skill-dir>/scripts/post_pr_review.py --pr <number> --findings /tmp/review-findings.json
```

The findings file looks like:

```json
{
  "summary": "Adds retry logic to the upload client. Solid overall; two correctness concerns and a missing test noted below.",
  "event": "COMMENT",
  "comments": [
    {"path": "src/upload.py", "line": 88, "body": "This retries on every exception, including auth failures that will never succeed. Catch only the transient ones (timeouts, 5xx)."},
    {"path": "src/upload.py", "start_line": 102, "line": 105, "body": "The backoff resets inside the loop, so it never actually grows. Move `delay` out of the loop body."}
  ]
}
```

Field notes:
- `event`: use `COMMENT` by default — it leaves feedback without approving or blocking the merge. Only use `APPROVE` or `REQUEST_CHANGES` if the user explicitly asks you to approve or request changes.
- `line`: the line in the head version of the file. For a multi-line range, add `start_line` (the range is `start_line`..`line`).
- `side`: defaults to `RIGHT` (the new version). You rarely need to set it.

The script resolves the repo automatically, posts the review in one API call, and — if an inline anchor turns out not to be in the diff — falls back to posting the summary with those findings folded into the body, so your review still lands. Read its output and relay what happened (posted with N inline comments, or fell back to summary-only).

### 6. Report back

Tell the user it's posted and link the PR (`gh pr view <number> --web` opens it, or just give the URL from step 2). Briefly recap the headline findings so they don't have to click through to know what you said.
