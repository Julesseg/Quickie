# GitHub CLI and API notes for babysit-pr

Substitute `{owner}`, `{repo}`, `{n}` (PR number). All of this needs `gh`
authenticated with the `repo` scope (`gh auth status`).

## What the watcher reads

- PR metadata: `gh pr view {n} --json number,url,state,mergedAt,closedAt,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus,reviewDecision`
- Checks: `gh pr checks {n} --json name,state,bucket,link,workflow,event,startedAt,completedAt`
  (`bucket` is `pass`, `fail`, `pending`, or `skipping`)
- Workflow runs for the head SHA: `gh api repos/{owner}/{repo}/actions/runs -X GET -f head_sha=<sha> -f per_page=100`
- Jobs of a run: `gh api repos/{owner}/{repo}/actions/runs/{run_id}/jobs -X GET -f per_page=100`
- Issue comments: `gh api repos/{owner}/{repo}/issues/{n}/comments --paginate`
- Inline review comments: `gh api repos/{owner}/{repo}/pulls/{n}/comments --paginate`
- Review submissions: `gh api repos/{owner}/{repo}/pulls/{n}/reviews --paginate`

Inline comments carry `pull_request_review_id`; a parent review still in
`PENDING` state is unpublished, and the watcher skips it and its comments
until it is submitted.

## Failed job logs

- Per job, available as soon as that job fails:
  `gh api repos/{owner}/{repo}/actions/jobs/{job_id}/logs > /tmp/job-{job_id}.zip`
  (the watcher lists these under `failed_jobs[].logs_endpoint`)
- Whole run, once it has finished: `gh run view <run-id> --log-failed`
- Rerun only the failed jobs: `gh run rerun <run-id> --failed`
  (what `--retry-failed-now` does, within the retry budget)

## Reading a comment

Pull the fields you need rather than the raw payload. `line` is null when
the comment sits on an outdated diff; fall back to `original_line`, and pull
`diff_hunk` only when the comment is unclear:

```sh
gh api repos/{owner}/{repo}/pulls/{n}/comments --paginate --jq '
  .[] | "── id:\(.id)  \(.path):\(.line // .original_line)\n   @\(.user.login): \(.body)\n"'
```

## Replying

Inline thread (the id is the REST `.id` of the thread's first comment):

```sh
gh api --method POST repos/{owner}/{repo}/pulls/{n}/comments/{comment_id}/replies \
  -f body="[agent] Done: switched to theme-aware colours, pushed in <sha>."
```

If that endpoint 404s on a given comment, post to the PR's comments with
`-F in_reply_to={comment_id}` instead:

```sh
gh api --method POST repos/{owner}/{repo}/pulls/{n}/comments \
  -f body="[agent] ..." -F in_reply_to={comment_id}
```

Conversation (PR-level) comment: `gh pr comment {n} --body "[agent] ..."`.

A `--jq` on a write runs after the write: a malformed filter makes `gh`
exit non-zero even though the reply landed, and a retry posts a duplicate.
Post without `--jq`, or with a real field like `--jq '.id'`. To remove a
stray reply: `gh api --method DELETE repos/{owner}/{repo}/pulls/comments/{reply_id}`.

## Resolving a thread (GraphQL)

Resolving takes the thread's GraphQL node id, correlated to the REST comment
id through the first comment's `databaseId`:

```sh
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes { id isResolved comments(first:1) { nodes { databaseId path } } }
      }
    }
  }
}' -f owner={owner} -f repo={repo} -F pr={n} --jq '
  .data.repository.pullRequest.reviewThreads.nodes[]
  | "\(.comments.nodes[0].databaseId)\t\(.id)\tresolved=\(.isResolved)\t\(.comments.nodes[0].path)"'
```

Match the `databaseId` to the REST `.id` of the thread you fixed, then:

```sh
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } }
}' -f threadId="PRRT_xxxxx"
```

Reply first, then resolve, so the reply lands before the thread collapses.
`-F pr={n}` (typed) for the `Int!`; `-f` would send a string and fail.
