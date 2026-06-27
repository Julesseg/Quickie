#!/usr/bin/env python3
"""PreToolUse hook: enforce Conventional Commits on every `git commit`.

Claude Code runs this before any Bash tool call. When the command is a
`git commit` carrying an inline message (`-m` / `--message`), the subject
line is validated against the Conventional Commits spec. A non-conforming
subject is blocked (exit code 2) with feedback, so the commit is rewritten
before it ever lands — making the convention deterministic rather than
relying on the model remembering to invoke the `conventional-commit` skill.

Deliberately permissive about what it lets through (it only ever blocks a
clearly-malformed inline subject):
  * non-Bash tools and any command without `git commit`
  * editor-driven commits / `--amend` with no new `-m`
  * git-generated subjects (Merge/Revert/fixup!/squash!)
  * messages built via command substitution `$(...)` or backticks,
    which can't be evaluated statically
  * unparseable commands (unbalanced quotes, etc.)

On any internal error it fails open (exit 0) so it can never wedge the agent.
"""

import json
import re
import shlex
import sys

TYPES = (
    "feat", "fix", "docs", "style", "refactor",
    "perf", "test", "build", "ci", "chore", "revert",
)
# <type>(<optional scope>)<optional !>: <description>
SUBJECT_RE = re.compile(rf"^(?:{'|'.join(TYPES)})(?:\([^()\n]+\))?!?: .+")
# Subjects git itself generates — never block these.
EXEMPT_RE = re.compile(r"^(?:Merge |Revert |fixup! |squash! )")


def allow():
    sys.exit(0)


def deny(subject):
    print(
        "Commit blocked: message does not follow Conventional Commits.\n"
        f"  Subject: {subject!r}\n"
        "  Required form: <type>(<optional scope>): <description>\n"
        f"  Allowed types: {', '.join(TYPES)}\n"
        "  Examples:\n"
        "    feat(launcher): add widget grid\n"
        "    fix: correct icon padding\n"
        "    docs: update README\n"
        "    feat!: drop iOS 16 support\n"
        "Rewrite the message (use the conventional-commit skill if helpful) "
        "and recommit.",
        file=sys.stderr,
    )
    sys.exit(2)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        allow()

    if payload.get("tool_name") != "Bash":
        allow()

    command = payload.get("tool_input", {}).get("command", "") or ""

    if "git" not in command or "commit" not in command:
        allow()

    # Dynamic message — can't validate statically, so don't get in the way.
    if "$(" in command or "`" in command:
        allow()

    try:
        tokens = shlex.split(command)
    except ValueError:
        allow()

    # Break the command into sub-commands on shell operators so a `git commit`
    # buried in `echo git commit ...` or after `&&` is judged at a real command
    # boundary rather than by naive substring matching.
    segments, current = [], []
    for t in tokens:
        if t in ("&&", "||", ";", "|", "&"):
            segments.append(current)
            current = []
        else:
            current.append(t)
    segments.append(current)

    messages = []
    for seg in segments:
        # A commit segment starts with `git` and uses the `commit` subcommand.
        if len(seg) < 2 or seg[0] != "git" or "commit" not in seg:
            continue
        i = 0
        while i < len(seg):
            t = seg[i]
            if t in ("-m", "--message"):
                if i + 1 < len(seg):
                    messages.append(seg[i + 1])
                    i += 2
                    continue
            elif t.startswith("--message="):
                messages.append(t.split("=", 1)[1])
            elif t.startswith("-m") and len(t) > 2:
                messages.append(t[2:])
            i += 1

    # No inline message (editor-driven or bare --amend): nothing to check.
    if not messages:
        allow()

    subject = messages[0].splitlines()[0].strip()
    if not subject or EXEMPT_RE.match(subject) or SUBJECT_RE.match(subject):
        allow()

    deny(subject)


if __name__ == "__main__":
    main()
