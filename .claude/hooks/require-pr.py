#!/usr/bin/env python3
"""Stop hook: no session ends with unshipped work.

Work in this repo ships as a pull request, always — but "remember to open a PR"
is a rule the model can simply fail to apply, and it has. Prose in AGENTS.md is
advisory; this is not. When the agent tries to finish a turn while changes sit
uncommitted, unpushed, or pushed with no PR, this blocks (exit 2) and hands back
the exact remaining step, the same way validate-commit-msg.py makes Conventional
Commits deterministic instead of remembered.

The three states it catches, in the order they must be resolved:

  1. Uncommitted work — modified tracked files or new untracked ones.
  2. Committed but unpushed — commits the remote has never seen.
  3. Pushed but no PR — a branch nobody can review or merge.

Deliberately never wedges the agent:
  * `stop_hook_active` means this hook already blocked once and the agent is
    stopping again anyway. It always allows then, so a genuine blocker (no
    remote, failing auth, a user who said "don't commit this") costs one
    reminder, not an infinite loop.
  * Being on the default branch is allowed through with a note to branch — the
    hook nudges, it does not invent a branch name or commit on the agent's
    behalf.
  * Every git/gh call is timeout-bounded, and ANY internal error or unexpected
    condition exits 0. A broken hook must never be able to trap a session.
"""

import json
import subprocess
import sys

TIMEOUT = 15


def allow():
    sys.exit(0)


def block(message):
    """Exit 2 — Claude Code feeds stderr back to the agent as instruction."""
    print(message, file=sys.stderr)
    sys.exit(2)


def git(*args, cwd):
    result = subprocess.run(
        ("git",) + args,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
    )
    return result.returncode, result.stdout.strip()


def main():
    payload = json.load(sys.stdin)

    # We already spoke up once this turn; never block twice.
    if payload.get("stop_hook_active"):
        allow()

    cwd = payload.get("cwd") or "."

    code, _ = git("rev-parse", "--git-dir", cwd=cwd)
    if code != 0:
        allow()

    _, branch = git("rev-parse", "--abbrev-ref", "HEAD", cwd=cwd)
    if not branch or branch == "HEAD":
        allow()  # detached; nothing sane to push

    _, status = git("status", "--porcelain", cwd=cwd)

    # The default branch is never the place to land work here, so the advice
    # differs: branch first, then the normal flow applies.
    if branch in ("main", "master"):
        if status:
            block(
                f"There are uncommitted changes on {branch}, which is the default "
                "branch. Create a feature branch, commit the work there, push it, "
                "and open a PR before finishing (AGENTS.md -> Every session that "
                "changes code ends in a pull request)."
            )
        allow()

    if status:
        changed = len(status.splitlines())
        block(
            f"{changed} file(s) are uncommitted on branch '{branch}'. Every session "
            "that changes code ends in a pull request (AGENTS.md). Commit the work "
            "with a Conventional Commits subject, push it, and open a PR with `gh "
            "pr create` before finishing. If the user explicitly asked you NOT to "
            "commit, say so plainly and stop again — this hook will not block twice."
        )

    # Unpushed commits: no upstream at all, or ahead of the one it has.
    code, upstream = git(
        "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", cwd=cwd
    )
    if code != 0:
        block(
            f"Branch '{branch}' has never been pushed. Push it (`git push -u origin "
            f"{branch}`) and open a PR with `gh pr create` before finishing "
            "(AGENTS.md -> Every session that changes code ends in a pull request)."
        )

    _, ahead = git("rev-list", "--count", f"{upstream}..HEAD", cwd=cwd)
    if ahead and ahead != "0":
        block(
            f"{ahead} commit(s) on '{branch}' are not pushed to {upstream}. Push "
            "them and make sure a PR is open before finishing."
        )

    # Nothing local is outstanding — is the work actually reviewable? A gh
    # failure here (offline, unauthenticated, no remote) is not the agent's
    # fault, so it never blocks.
    try:
        result = subprocess.run(
            ["gh", "pr", "view", branch, "--json", "url,state"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
        )
    except Exception:
        allow()

    if result.returncode != 0:
        if "no pull requests found" in (result.stderr or "").lower():
            block(
                f"Branch '{branch}' is pushed but has no pull request. Open one with "
                "`gh pr create` (Conventional Commits title, same as the commit "
                "subject) before finishing — AGENTS.md -> Every session that changes "
                "code ends in a pull request."
            )
        allow()  # any other gh failure: not something the agent can fix here

    allow()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        allow()
