#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AgentHookTests(unittest.TestCase):
    def check_commit(self, client, command):
        return subprocess.run(
            [sys.executable, str(ROOT / ".agents/hooks/dispatch.py"), client, "validate-commit-msg"],
            input=json.dumps({"cwd": str(ROOT), "tool_name": "Bash", "tool_input": {"command": command}}),
            text=True, capture_output=True,
        )

    def test_normalized_codex_and_claude_commands_reject_invalid_commit(self):
        for client in ("codex", "claude"):
            with self.subTest(client=client):
                result = self.check_commit(client, "git commit -m 'unstructured subject'")
                self.assertEqual(result.returncode, 2)
                self.assertIn("Commit blocked", result.stderr)

    def test_conventional_subject_passes(self):
        result = self.check_commit("codex", "git commit -m 'chore(agents): adopt T3 Code'")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_merge_subject_passes(self):
        result = self.check_commit("codex", "git commit -m 'Merge branch main'")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
