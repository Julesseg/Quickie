#!/usr/bin/env python3
"""Translate Claude or Codex hook payloads into the shared hook contract."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


def payload() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def project_root(client: str, data: dict) -> Path:
    explicit = data.get("cwd")
    if client == "claude":
        explicit = os.environ.get("CLAUDE_PROJECT_DIR") or explicit
    if explicit:
        return Path(explicit).resolve()
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    return Path(result.stdout.strip() or os.getcwd()).resolve()


def edited_path(data: dict) -> str:
    tool_input = data.get("tool_input") or {}
    for key in ("file_path", "filePath", "path"):
        if tool_input.get(key):
            return str(tool_input[key])
    command = str(tool_input.get("command") or "")
    match = re.search(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", command, re.MULTILINE)
    return match.group(1) if match else ""


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: dispatch.py <claude|codex> <event>", file=sys.stderr)
        return 2

    client, event = sys.argv[1:]
    data = payload()
    root = project_root(client, data)
    tool_input = data.get("tool_input") or {}
    env = os.environ.copy()
    env.update(
        AGENT_PROJECT_DIR=str(root),
        AGENT_REMOTE=(
            os.environ.get("AGENT_REMOTE")
            or (os.environ.get("CLAUDE_CODE_REMOTE", "false") if client == "claude" else "false")
        ),
        AGENT_ENV_FILE=(
            os.environ.get("CLAUDE_ENV_FILE", "")
            if client == "claude"
            else os.environ.get("AGENT_ENV_FILE", "")
        ),
        AGENT_SESSION_ID=str(data.get("session_id") or "session"),
        AGENT_TOOL_NAME=str(data.get("tool_name") or ""),
        AGENT_COMMAND=str(tool_input.get("command") or ""),
        AGENT_FILE_PATH=edited_path(data),
    )

    suffix = ".py" if event == "validate-commit-msg" else ".sh"
    script = root / ".agents" / "hooks" / f"{event}{suffix}"
    if not script.exists():
        return 0

    result = subprocess.run(
        [str(script)],
        check=False,
        capture_output=True,
        text=True,
        env=env,
        cwd=root,
    )
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)

    output = result.stdout.strip()
    if event == "stop" and result.returncode != 0:
        reason = output or result.stderr.strip() or "Repository checks failed. Fix them before stopping."
        if client == "codex":
            print(json.dumps({"decision": "block", "reason": reason}))
            return 0
        print(reason, file=sys.stderr)
        return 2

    if client == "codex" and output and event == "post-edit":
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": output,
            }
        }))
    elif output:
        print(output)

    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
