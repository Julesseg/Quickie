# GitHub PR review API cookbook

Exact `gh` commands for each phase. Substitute `{owner}`, `{repo}`, `{n}` (PR number).

- [Find the PR and repo](#find-the-pr-and-repo)
- [Fetch all feedback](#fetch-all-feedback)
- [Reply to a thread](#reply-to-a-thread)
- [Resolve a thread (GraphQL)](#resolve-a-thread-graphql)
- [Gotchas](#gotchas)

## Find the PR and repo

```bash
# owner/repo for the current checkout
gh repo view --json owner,name --jq '.owner.login + "/" + .name'

# PR number for the current branch (if the user didn't give one)
gh pr view --json number --jq '.number'
```

## Fetch all feedback

Three surfaces, three endpoints. Pull all three — they don't overlap.

```bash
# 1. Inline review comments (line-anchored) — usually the substance.
#    `gh pr view --comments` does NOT include these.
gh api repos/{owner}/{repo}/pulls/{n}/comments --paginate

# 2. Review summaries (the body of each submitted review)
gh api repos/{owner}/{repo}/pulls/{n}/reviews --paginate

# 3. Conversation comments (general, not line-anchored)
gh api repos/{owner}/{repo}/issues/{n}/comments --paginate
```

Don't dump raw JSON into context. Extract the fields you need per inline comment with `--jq` — note `.id` (needed to reply) and fall back to `original_line` when `line` is null (the comment is on an outdated diff):

```bash
gh api repos/{owner}/{repo}/pulls/{n}/comments --paginate --jq '
  .[] | "── id:\(.id)  \(.path):\(.line // .original_line)\n   @\(.user.login): \(.body)\n"'
```

If you want the diff hunk for context, add `\(.diff_hunk)` — but it's verbose, so pull it only when a comment is unclear.

## Reply to a thread

Posting to the **first comment's id** adds your reply to that thread:

```bash
gh api --method POST \
  repos/{owner}/{repo}/pulls/{n}/comments/{comment_id}/replies \
  -f body="Done — switched to theme-aware colors. Pushed in <sha>."
```

`{comment_id}` is the REST `.id` from the pulls/comments fetch above.

## Resolve a thread (GraphQL)

Resolving needs the **GraphQL thread node id**, which is *not* the REST comment id. You correlate the two through the thread's first comment's `databaseId` (that databaseId equals the REST `.id`).

**Step 1 — list threads with both ids:**

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          comments(first:1) { nodes { databaseId path } }
        }
      }
    }
  }
}' -f owner={owner} -f repo={repo} -F pr={n} --jq '
  .data.repository.pullRequest.reviewThreads.nodes[]
  | "\(.comments.nodes[0].databaseId)\t\(.id)\tresolved=\(.isResolved)\t\(.comments.nodes[0].path)"'
```

This prints `databaseId <tab> threadNodeId <tab> resolved <tab> path`. Match the `databaseId` to the REST comment `.id` of the thread you fixed to get its `threadNodeId` (looks like `PRRT_...`).

**Step 2 — resolve it:**

```bash
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) {
    thread { isResolved }
  }
}' -f threadId="PRRT_xxxxx"
```

Reply first (Step in the SKILL flow), then resolve, so the reply lands in the thread before it's collapsed.

## Gotchas

- **`-f` vs `-F`:** `-f` sends a string; `-F` sends a typed value. The PR number is an `Int!`, so it must be `-F pr={n}` — using `-f` makes it a string and the query errors.
- **Pagination:** `reviewThreads(first:100)` covers almost every PR. If a review genuinely has >100 threads, page with `after:` cursors.
- **Outdated comments:** when the code under a comment changed, `.line` is `null`; use `.original_line` and `.diff_hunk` to locate what the reviewer meant.
- **Don't resolve what you disagreed with:** if you pushed back instead of changing code, reply with your reasoning and leave the thread open for the reviewer.
- **`--jq` runs *after* the write — never use it as a success check.** `gh` performs the POST/mutation, then applies `--jq` to the response. A malformed `--jq` makes `gh` exit non-zero even though the write already landed server-side. If you treat that exit code as "it failed" and retry, you post a **duplicate reply**. When posting in a loop, either drop `--jq` or use a real field like `--jq '.id'`; to confirm a reply landed, re-fetch the thread, don't trust a hand-rolled format string. To remove a stray reply: `gh api --method DELETE repos/{owner}/{repo}/pulls/comments/{reply_id}`.
- **Scope:** posting replies and `resolveReviewThread` both need the `repo` OAuth scope (`gh auth status` to check).
