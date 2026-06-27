---
name: resolve-review-threads
description: Resolve GitHub pull-request review threads through the GitHub MCP tools (mcp__github__*) when the gh CLI is unavailable. Use when you need to mark PR review threads as resolved (not just reply) in an environment with only MCP GitHub tools — resolve_review_thread requires a PRRT_ thread node ID that get_review_comments never returns, so this skill reconstructs it from pagination cursors. Triggers include "resolve the review threads", "mark the threads resolved", or closing threads after replying to PR comments when gh isn't installed.
---

# Resolve PR review threads (MCP, no gh)

Replying to a review comment and resolving its thread use two different IDs:

- **Reply** → `mcp__github__add_reply_to_pull_request_comment` needs the REST **comment id** (the number in a comment's `html_url`, e.g. `#discussion_r3304458907` → `3304458907`).
- **Resolve** → `mcp__github__resolve_review_thread` needs the GraphQL **thread node id** (`PRRT_…`), which `get_review_comments` does **not** return.

This skill reconstructs the `PRRT_` ids from the pagination cursors.

## Workflow

1. **Address + reply first.** Fix the code (or push back), then post one reply per thread with `add_reply_to_pull_request_comment`. Keep any one reply's response `node_id` (a `PRRC_…` string) — it carries the repo bytes. Reply before resolving so the note lands before the thread collapses.

2. **Collect each thread's cursor.** `get_review_comments` returns threads in order but no thread ids. Call it once per thread with `perPage = k`; the k-th thread's cursor is `pageInfo.endCursor`:
   - `perPage:1` → thread 1's cursor, `perPage:2` → thread 2's, and so on.
   - An initial `perPage:100` reads `totalCount` (how many threads there are).

3. **Reconstruct the PRRT ids** with the bundled script (deterministic — don't hand-roll the bytes):
   ```bash
   python3 scripts/thread_ids.py <PRRC_node_id> <cursor1> <cursor2> ...
   ```
   It prints one `PRRT_…` id per cursor, in the order given.

4. **Resolve** each thread you actually addressed:
   `mcp__github__resolve_review_thread(owner, repo, threadId="PRRT_…")`.

## How the ids encode (background)

A `PRRT_` / `PRRC_` node id is `urlsafe_b64( \x93\x00 + repo_bytes(6) + db_id(4) )`:

- **repo_bytes** are constant per repo — bytes 2–7 of any `PRRC_` comment node id.
- **thread db id** is the trailing 4 bytes (big-endian uint32) of the thread's cursor (the cursor is base64 of msgpack `[timestamp, uint32_thread_id]`).

`scripts/thread_ids.py` does the decode/encode for you.

## Gotchas

- **Reply, then resolve** — order matters so the reply is visible inside the thread.
- **Don't resolve disagreements.** If you pushed back instead of changing code, leave the thread open for the reviewer.
- **Match before resolving.** Map cursors to threads via each thread's comment `path`/`line` in the `get_review_comments` output, and only resolve the ones you fixed.
- The MCP GitHub server must be authorized to write PR comments and resolve threads.
- For the full "gather → investigate → fix → verify → reply" review loop, see the `address-pr-review` skill; this skill is only the MCP resolve step.
