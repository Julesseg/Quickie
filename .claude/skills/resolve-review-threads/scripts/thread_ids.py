#!/usr/bin/env python3
"""Reconstruct GitHub PRRT_ review-thread node IDs for mcp__github__resolve_review_thread.

The GitHub MCP `get_review_comments` method does not return thread node IDs, but
`resolve_review_thread` requires them. This rebuilds each PRRT_ id from:

  - repo bytes: taken from any PRRC_ comment node id (e.g. the `node_id` returned
    when you post a reply with add_reply_to_pull_request_comment).
  - thread db id: the last 4 bytes of each thread's pagination cursor (get the
    k-th thread's cursor as pageInfo.endCursor by calling get_review_comments
    with perPage=k).

Usage:
  python3 thread_ids.py <PRRC_node_id> <cursor1> [<cursor2> ...]

Prints one PRRT_ id per input cursor, in the order given.
"""
import base64
import sys


def _b64(s: str) -> bytes:
    # Accept both standard (cursors) and URL-safe (node ids) base64, unpadded.
    s = s.replace("-", "+").replace("_", "/")
    return base64.b64decode(s + "=" * (-len(s) % 4))


def repo_bytes(prrc_node_id: str) -> bytes:
    # PRRC_<base64>; decoded layout is [type(2)][repo(6)][comment_db_id(rest)].
    return _b64(prrc_node_id.split("_", 1)[1])[2:8]


def thread_id_bytes(cursor: str) -> bytes:
    # Cursor is base64 of msgpack [timestamp, uint32_thread_id]; id is the tail.
    return _b64(cursor)[-4:]


def build_prrt(repo_b: bytes, tid_b: bytes) -> str:
    enc = base64.b64encode(b"\x93\x00" + repo_b + tid_b).decode()
    return "PRRT_" + enc.replace("+", "-").replace("/", "_").rstrip("=")


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 1
    rb = repo_bytes(argv[1])
    for cursor in argv[2:]:
        print(build_prrt(rb, thread_id_bytes(cursor)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
