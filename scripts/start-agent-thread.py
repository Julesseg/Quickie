#!/usr/bin/env python3
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


BUSY_STATES = {"preparing", "queued", "starting", "running", "waiting"}


def active_dispatches(threads):
    if not isinstance(threads, list) or any(
        not isinstance(thread, dict) or not {"threadId", "status", "branch"} <= thread.keys()
        for thread in threads
    ):
        raise ValueError("Invalid T3 thread listing; host capacity cannot be checked")
    return sum(
        thread["status"] in BUSY_STATES
        and not thread.get("parentThreadId")
        and bool(re.fullmatch(r"agent/issue-[1-9][0-9]*", thread["branch"] or ""))
        for thread in threads
    )


def registry_path(env):
    if env.get("T3_DISPATCH_STATE"):
        path = Path(env["T3_DISPATCH_STATE"]).expanduser()
        if not path.is_absolute():
            raise ValueError("T3_DISPATCH_STATE must be one shared absolute path")
        return path
    server_home = Path(env.get("T3_BASE_DIR") or env.get("T3CODE_HOME") or Path.home() / ".t3").expanduser().resolve()
    identity = hashlib.sha256(str(server_home).encode()).hexdigest()[:16]
    return Path.home() / ".local/state/t3-agent-implement" / (identity + ".json")


def start(env):
    issue = env.get("ISSUE", "")
    if not re.fullmatch(r"[1-9][0-9]*", issue):
        raise ValueError("ISSUE must be a positive issue number")
    if not env.get("T3_PROJECT_DIR", "").strip():
        raise ValueError("Set the T3_PROJECT_DIR repository Actions variable")
    project = Path(env["T3_PROJECT_DIR"]).expanduser()
    if not project.is_absolute() or not project.is_dir():
        raise ValueError("T3_PROJECT_DIR must be an existing absolute checkout path")
    project = project.resolve()
    cli = str(Path(env.get("T3_CLI") or shutil.which("t3") or Path.home() / ".t3/bin/t3").expanduser())
    base_arguments = ["--base-dir", env["T3_BASE_DIR"]] if env.get("T3_BASE_DIR") else []
    state_path = registry_path(env)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with state_path.open("a+", encoding="utf-8") as state:
        fcntl.flock(state, fcntl.LOCK_EX)
        state.seek(0)
        raw = state.read()
        projects = json.loads(raw) if raw else []
        if not isinstance(projects, list) or any(
            not isinstance(path, str) or not Path(path).is_absolute() for path in projects
        ):
            raise ValueError("Invalid shared dispatch registry; host capacity cannot be checked")
        projects = sorted(set(projects) | {str(project)})
        state.seek(0)
        state.truncate()
        json.dump(projects, state)
        state.flush()
        os.fsync(state.fileno())
        busy = 0
        for path in projects:
            result = subprocess.run(
                [cli, "thread", "list", "--project", path, "--json", *base_arguments],
                check=True, capture_output=True, text=True, timeout=60,
            )
            busy += active_dispatches(json.loads(result.stdout))
        if busy >= 3:
            print(f"::notice::Not spawning: {busy} automated T3 threads are active; host limit is 3")
            return False
        subprocess.run(["git", "-C", str(project), "fetch", "--prune", "origin"], check=True, timeout=120)
        result = subprocess.run(
            [
                cli, "thread", "start", str(project),
                f"Use the label-and-implement-with-pr skill to implement issue #{issue}. "
                "Read AGENTS.md and docs/agents/t3-code.md before starting.",
                "--title", f"Agent implement: issue #{issue}",
                "--worktree", env.get("T3_BASE") or "origin/main",
                "--branch", f"agent/issue-{issue}", "--json", *base_arguments,
            ],
            check=True, capture_output=True, text=True, timeout=120,
        )
        receipt = json.loads(result.stdout)
        if not isinstance(receipt, dict) or not isinstance(receipt.get("threadId"), str):
            raise ValueError("T3 returned no thread receipt; inspect existing threads before retrying")
        print(result.stdout, end="")
        return True


if __name__ == "__main__":
    try:
        start(os.environ)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"::error::Cannot start T3 thread: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
