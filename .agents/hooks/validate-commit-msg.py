#!/usr/bin/env python3
"""Validate inline git commit subjects from normalized agent hook input."""

import os
import re
import shlex
import sys

TYPES = (
    "feat", "fix", "docs", "style", "refactor", "perf", "test", "build",
    "ci", "chore", "revert",
)
SUBJECT_RE = re.compile(rf"^(?:{'|'.join(TYPES)})(?:\([^()\n]+\))?!?: .+")
EXEMPT_RE = re.compile(r"^(?:Merge |Revert |fixup! |squash! )")


def deny(subject: str) -> None:
    print(
        "Commit blocked: message does not follow Conventional Commits.\n"
        f"  Subject: {subject!r}\n"
        "  Required form: <type>(<optional scope>): <description>\n"
        f"  Allowed types: {', '.join(TYPES)}\n"
        "Rewrite the message and recommit.",
        file=sys.stderr,
    )
    raise SystemExit(2)


def main() -> None:
    if os.environ.get("AGENT_TOOL_NAME", "").lower() not in {"bash", "shell"}:
        return

    command = os.environ.get("AGENT_COMMAND", "")
    if "git" not in command or "commit" not in command or "$(" in command or "`" in command:
        return

    try:
        tokens = shlex.split(command)
    except ValueError:
        return

    segments: list[list[str]] = [[]]
    for token in tokens:
        if token in {"&&", "||", ";", "|", "&"}:
            segments.append([])
        else:
            segments[-1].append(token)

    messages: list[str] = []
    for segment in segments:
        if len(segment) < 2 or segment[0] != "git" or "commit" not in segment:
            continue
        index = 0
        while index < len(segment):
            token = segment[index]
            if token in {"-m", "--message"} and index + 1 < len(segment):
                messages.append(segment[index + 1])
                index += 2
                continue
            if token.startswith("--message="):
                messages.append(token.split("=", 1)[1])
            elif token.startswith("-m") and len(token) > 2:
                messages.append(token[2:])
            index += 1

    if not messages:
        return

    subject = messages[0].splitlines()[0].strip()
    if subject and not EXEMPT_RE.match(subject) and not SUBJECT_RE.match(subject):
        deny(subject)


if __name__ == "__main__":
    main()
