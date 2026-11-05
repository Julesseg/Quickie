#!/usr/bin/env python3
import contextlib
import fcntl
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("agent_dispatch", Path(__file__).with_name("start-agent-thread.py"))
dispatch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatch)


def response(value):
    return subprocess.CompletedProcess([], 0, stdout=json.dumps(value), stderr="")


def thread(number, status="running", branch=None, parent=None):
    return {
        "threadId": str(number), "status": status,
        "branch": branch or f"agent/issue-{number}", "parentThreadId": parent,
    }


class AgentDispatchTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="agent dispatch ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.state = self.root / "shared.json"
        self.env = {
            "ISSUE": "42", "T3_PROJECT_DIR": str(self.root),
            "T3_CLI": "/tools/t3", "T3_DISPATCH_STATE": str(self.state),
        }

    def start(self, run, listings=None):
        run.side_effect = [response(items) for items in (listings or [[]])] + [response(None), response({"threadId": "new"})]
        with contextlib.redirect_stdout(io.StringIO()):
            return dispatch.start(self.env)

    @patch.object(dispatch.subprocess, "run")
    def test_ready_server_fetches_before_starting_an_isolated_thread(self, run):
        self.assertTrue(self.start(run))
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], ["/tools/t3", "thread", "list", "--project", str(self.root), "--json"])
        self.assertEqual(commands[1], ["git", "-C", str(self.root), "fetch", "--prune", "origin"])
        self.assertEqual(commands[2][:4], ["/tools/t3", "thread", "start", str(self.root)])
        self.assertIn("issue #42", commands[2][4])
        self.assertEqual(commands[2][5:], [
            "--title", "Agent implement: issue #42", "--worktree", "origin/main",
            "--branch", "agent/issue-42", "--json",
        ])

    @patch.object(dispatch.subprocess, "run")
    def test_capacity_is_shared_across_registered_projects(self, run):
        other = str(self.root / "other")
        self.state.write_text(json.dumps([other]))
        run.side_effect = [response([thread(1), thread(2)]), response([thread(3)])]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertFalse(dispatch.start(self.env))
        self.assertEqual(run.call_count, 2)
        self.assertEqual(set(json.loads(self.state.read_text())), {str(self.root), other})

    def test_idle_manual_and_child_threads_do_not_consume_capacity(self):
        self.assertEqual(dispatch.active_dispatches([
            thread(1, status="completed"), thread(2, branch="feature/manual"),
            thread(3, parent="parent"), thread(4),
        ]), 1)

    @patch.object(dispatch.subprocess, "run")
    def test_listing_and_launch_share_one_host_lock(self, run):
        def request(*args, **kwargs):
            with self.state.open("a+") as contender:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if args[0][1:3] == ["thread", "list"]:
                return response([])
            if args[0][1:3] == ["thread", "start"]:
                return response({"threadId": "new"})
            return response(None)
        run.side_effect = request
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(dispatch.start(self.env))

    @patch.object(dispatch.subprocess, "run")
    def test_custom_base_and_server_home(self, run):
        self.env.update(T3_BASE="origin/release", T3_BASE_DIR="/custom t3")
        self.start(run)
        commands = [call.args[0] for call in run.call_args_list]
        for command in (commands[0], commands[2]):
            self.assertEqual(command[-2:], ["--base-dir", "/custom t3"])
        self.assertEqual(commands[2][commands[2].index("--worktree") + 1], "origin/release")

    @patch.object(dispatch.subprocess, "run")
    def test_invalid_issue_or_configuration_starts_nothing(self, run):
        for values in ({"ISSUE": "0"}, {"ISSUE": "42; touch /tmp/unwanted"}, {"T3_PROJECT_DIR": ""}, {"T3_PROJECT_DIR": "relative"}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                dispatch.start({**self.env, **values})
        run.assert_not_called()

    @patch.object(dispatch.subprocess, "run")
    def test_corrupt_registry_fails_closed(self, run):
        for contents in ("invalid json", "{}", '["relative"]'):
            self.state.write_text(contents)
            with self.subTest(contents=contents), self.assertRaises(ValueError):
                dispatch.start(self.env)
        run.assert_not_called()

    @patch.object(dispatch.subprocess, "run")
    def test_unavailable_server_prevents_fetch_and_launch(self, run):
        run.side_effect = subprocess.CalledProcessError(1, "t3")
        with self.assertRaises(subprocess.CalledProcessError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 1)

    @patch.object(dispatch.subprocess, "run")
    def test_malformed_listing_prevents_launch(self, run):
        run.return_value = response({"error": "offline"})
        with self.assertRaises(ValueError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 1)

    @patch.object(dispatch.subprocess, "run")
    def test_fetch_failure_prevents_launch(self, run):
        run.side_effect = [response([]), subprocess.CalledProcessError(1, "git")]
        with self.assertRaises(subprocess.CalledProcessError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 2)

    @patch.object(dispatch.subprocess, "run")
    def test_launch_failure_is_not_retried(self, run):
        run.side_effect = [response([]), response(None), subprocess.CalledProcessError(1, "t3")]
        with self.assertRaises(subprocess.CalledProcessError):
            dispatch.start(self.env)
        self.assertEqual(run.call_count, 3)



    def test_concurrent_launchers_enforce_the_shared_host_limit(self):
        import os
        import sys
        launcher = self.root / "t3"
        launcher.write_text("#!" + sys.executable + "\n" + """import json
from pathlib import Path
import sys
import time
args = sys.argv[1:]
ledger = Path(__file__).with_name('launched.jsonl')
if args[:2] == ['thread', 'list']:
    project = args[args.index('--project') + 1]
    rows = [json.loads(line) for line in ledger.read_text().splitlines()] if ledger.exists() else []
    print(json.dumps([row for row in rows if row['project'] == project]))
else:
    time.sleep(0.05)
    row = {'threadId': args[2], 'project': args[2], 'status': 'running', 'branch': args[args.index('--branch') + 1]}
    with ledger.open('a') as output:
        output.write(json.dumps(row) + '\\n')
    print(json.dumps({'threadId': args[2]}))
""")
        launcher.chmod(0o755)
        git = self.root / "git"
        git.write_text("#!/bin/sh\nexit 0\n")
        git.chmod(0o755)
        processes = []
        for number in range(4):
            project = self.root / str(number)
            project.mkdir()
            environment = {
                **os.environ, **self.env, "T3_PROJECT_DIR": str(project),
                "T3_CLI": str(launcher), "PATH": str(self.root) + os.pathsep + os.environ["PATH"],
            }
            processes.append(subprocess.Popen(
                [sys.executable, "-B", str(Path(dispatch.__file__))], env=environment,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ))
        outputs = [process.communicate(timeout=20) for process in processes]
        self.assertEqual([process.returncode for process in processes], [0] * 4, outputs)
        launched = (self.root / "launched.jsonl").read_text().splitlines()
        self.assertEqual(len(launched), 3)
        self.assertEqual(sum("Not spawning" in output for output, _ in outputs), 1)



    def test_relative_registry_override_fails_in_every_checkout(self):
        for name in ("checkout-a", "checkout-b"):
            checkout = self.root / name
            checkout.mkdir()
            with contextlib.chdir(checkout), self.assertRaisesRegex(ValueError, "absolute"):
                dispatch.registry_path({**self.env, "T3_DISPATCH_STATE": "dispatch.json"})


if __name__ == "__main__":
    unittest.main()
