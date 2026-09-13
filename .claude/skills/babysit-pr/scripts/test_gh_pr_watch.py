import argparse
import importlib.util
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).with_name("gh_pr_watch.py")
MODULE_SPEC = importlib.util.spec_from_file_location("gh_pr_watch", MODULE_PATH)
gh_pr_watch = importlib.util.module_from_spec(MODULE_SPEC)
assert MODULE_SPEC.loader is not None
MODULE_SPEC.loader.exec_module(gh_pr_watch)


def sample_pr():
    return {
        "number": 123,
        "url": "https://github.com/openai/codex/pull/123",
        "repo": "openai/codex",
        "head_sha": "abc123",
        "head_branch": "feature",
        "state": "OPEN",
        "merged": False,
        "closed": False,
        "mergeable": "MERGEABLE",
        "merge_state_status": "CLEAN",
        "review_decision": "",
    }


def sample_checks(**overrides):
    checks = {
        "pending_count": 0,
        "failed_count": 0,
        "passed_count": 12,
        "all_terminal": True,
    }
    checks.update(overrides)
    return checks


def test_collect_snapshot_fetches_review_items_before_ci(monkeypatch, tmp_path):
    call_order = []
    pr = sample_pr()

    monkeypatch.setattr(gh_pr_watch, "resolve_pr", lambda *args, **kwargs: pr)
    monkeypatch.setattr(gh_pr_watch, "load_state", lambda path: ({}, True))
    monkeypatch.setattr(
        gh_pr_watch,
        "get_authenticated_login",
        lambda: call_order.append("auth") or "octocat",
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "fetch_new_review_items",
        lambda *args, **kwargs: call_order.append("review") or [],
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "get_pr_checks",
        lambda *args, **kwargs: call_order.append("checks") or [],
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "summarize_checks",
        lambda checks: call_order.append("summarize") or sample_checks(),
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "get_workflow_runs_for_sha",
        lambda *args, **kwargs: call_order.append("workflow") or [],
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "failed_runs_from_workflow_runs",
        lambda *args, **kwargs: call_order.append("failed_runs") or [],
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "failed_jobs_from_workflow_runs",
        lambda *args, **kwargs: call_order.append("failed_jobs") or [],
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "recommend_actions",
        lambda *args, **kwargs: call_order.append("recommend") or ["idle"],
    )
    monkeypatch.setattr(gh_pr_watch, "save_state", lambda *args, **kwargs: None)

    args = argparse.Namespace(
        pr="123",
        repo=None,
        state_file=str(tmp_path / "watcher-state.json"),
        max_flaky_retries=3,
    )

    gh_pr_watch.collect_snapshot(args)

    assert call_order.index("review") < call_order.index("checks")
    assert call_order.index("review") < call_order.index("workflow")


def test_recommend_actions_prioritizes_review_comments():
    actions = gh_pr_watch.recommend_actions(
        sample_pr(),
        sample_checks(failed_count=1),
        [{"run_id": 99}],
        [],
        [{"kind": "review_comment", "id": "1"}],
        0,
        3,
    )

    assert actions == [
        "process_review_comment",
        "diagnose_ci_failure",
        "retry_failed_checks",
    ]


def test_pending_review_feedback_surfaces_only_after_publication(monkeypatch):
    state = {
        "seen_review_comment_ids": ["20"],
        "seen_review_ids": ["10"],
    }
    review = {
        "id": 10,
        "user": {"login": "octocat"},
        "author_association": "MEMBER",
        "state": "PENDING",
        "body": "Please rename this.",
        "created_at": "2026-06-08T10:00:00Z",
        "submitted_at": None,
        "html_url": "https://github.com/openai/codex/pull/123#pullrequestreview-10",
    }
    review_comment = {
        "id": 20,
        "pull_request_review_id": 10,
        "user": {"login": "octocat"},
        "author_association": "MEMBER",
        "body": "Please rename this.",
        "created_at": "2026-06-08T10:00:00Z",
        "path": "src/example.rs",
        "line": 7,
        "html_url": "https://github.com/openai/codex/pull/123#discussion_r20",
    }

    def fake_list(endpoint, **kwargs):
        if endpoint.endswith("/issues/123/comments"):
            return []
        if endpoint.endswith("/pulls/123/comments"):
            return [review_comment]
        if endpoint.endswith("/pulls/123/reviews"):
            return [review]
        raise AssertionError(f"unexpected endpoint: {endpoint}")

    monkeypatch.setattr(gh_pr_watch, "gh_api_list_paginated", fake_list)

    assert (
        gh_pr_watch.fetch_new_review_items(
            sample_pr(),
            state,
            fresh_state=True,
            authenticated_login="octocat",
        )
        == []
    )
    assert state["seen_review_comment_ids"] == []
    assert state["seen_review_ids"] == []

    review["state"] = "COMMENTED"
    review["submitted_at"] = "2026-06-08T10:05:00Z"

    published_items = gh_pr_watch.fetch_new_review_items(
        sample_pr(),
        state,
        fresh_state=False,
        authenticated_login="octocat",
    )

    assert {(item["kind"], item["id"]) for item in published_items} == {
        ("review", "10"),
        ("review_comment", "20"),
    }
    assert state["seen_review_comment_ids"] == ["20"]
    assert state["seen_review_ids"] == ["10"]


def test_run_watch_keeps_polling_open_ready_to_merge_pr(monkeypatch):
    sleeps = []
    events = []
    snapshot = {
        "pr": sample_pr(),
        "checks": sample_checks(),
        "failed_runs": [],
        "failed_jobs": [],
        "new_review_items": [],
        "actions": ["ready_to_merge"],
        "retry_state": {
            "current_sha_retries_used": 0,
            "max_flaky_retries": 3,
        },
    }

    monkeypatch.setattr(
        gh_pr_watch,
        "collect_snapshot",
        lambda args: (snapshot, Path("/tmp/babysit-pr-state.json")),
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "print_event",
        lambda event, payload: events.append((event, payload)),
    )

    class StopWatch(Exception):
        pass

    def fake_sleep(seconds):
        sleeps.append(seconds)
        if len(sleeps) >= 2:
            raise StopWatch

    monkeypatch.setattr(gh_pr_watch.time, "sleep", fake_sleep)

    with pytest.raises(StopWatch):
        gh_pr_watch.run_watch(
            argparse.Namespace(poll_seconds=30, until_change=False, max_wait=0)
        )

    assert sleeps == [30, 30]
    assert [event for event, _ in events] == ["snapshot", "snapshot"]


def test_failed_jobs_include_direct_logs_endpoint(monkeypatch):
    jobs_by_run = {
        99: [
            {
                "id": 555,
                "name": "unit tests",
                "status": "completed",
                "conclusion": "failure",
                "html_url": "https://github.com/openai/codex/actions/runs/99/job/555",
            },
            {
                "id": 556,
                "name": "lint",
                "status": "completed",
                "conclusion": "success",
            },
        ]
    }

    monkeypatch.setattr(
        gh_pr_watch,
        "get_jobs_for_run",
        lambda repo, run_id: jobs_by_run[run_id],
    )

    failed_jobs = gh_pr_watch.failed_jobs_from_workflow_runs(
        "openai/codex",
        [
            {
                "id": 99,
                "name": "CI",
                "status": "in_progress",
                "conclusion": "",
                "head_sha": "abc123",
            }
        ],
        "abc123",
    )

    assert failed_jobs == [
        {
            "run_id": 99,
            "workflow_name": "CI",
            "run_status": "in_progress",
            "run_conclusion": "",
            "job_id": 555,
            "job_name": "unit tests",
            "status": "completed",
            "conclusion": "failure",
            "html_url": "https://github.com/openai/codex/actions/runs/99/job/555",
            "logs_endpoint": "repos/openai/codex/actions/jobs/555/logs",
        }
    ]


def _watch_args(**overrides):
    base = {"poll_seconds": 30, "until_change": True, "max_wait": 0}
    base.update(overrides)
    return argparse.Namespace(**base)


def _snapshot(actions, **pr_overrides):
    pr = sample_pr()
    pr.update(pr_overrides)
    return {
        "pr": pr,
        "checks": sample_checks(),
        "failed_runs": [],
        "failed_jobs": [],
        "new_review_items": [],
        "actions": actions,
        "retry_state": {"current_sha_retries_used": 0, "max_flaky_retries": 3},
    }


def test_until_change_exits_immediately_when_action_needed(monkeypatch):
    events = []
    monkeypatch.setattr(
        gh_pr_watch,
        "collect_snapshot",
        lambda args: (_snapshot(["process_review_comment"]), Path("/tmp/s.json")),
    )
    monkeypatch.setattr(
        gh_pr_watch, "print_event", lambda e, p: events.append((e, p))
    )
    monkeypatch.setattr(
        gh_pr_watch.time, "sleep", lambda s: pytest.fail("should not sleep")
    )

    assert gh_pr_watch.run_watch(_watch_args()) == 0
    assert [e for e, _ in events] == ["snapshot", "action_needed"]
    assert events[-1][1]["actions"] == ["process_review_comment"]


def test_until_change_keeps_polling_quiet_pr_then_exits_on_change(monkeypatch):
    events = []
    snapshots = iter(
        [
            _snapshot(["ready_to_merge"]),
            _snapshot(["ready_to_merge"]),
            _snapshot(["idle"], merge_state_status="BEHIND"),
        ]
    )
    monkeypatch.setattr(
        gh_pr_watch,
        "collect_snapshot",
        lambda args: (next(snapshots), Path("/tmp/s.json")),
    )
    monkeypatch.setattr(
        gh_pr_watch, "print_event", lambda e, p: events.append((e, p))
    )
    sleeps = []
    monkeypatch.setattr(gh_pr_watch.time, "sleep", lambda s: sleeps.append(s))

    assert gh_pr_watch.run_watch(_watch_args()) == 0
    assert sleeps == [30, 30]
    assert [e for e, _ in events] == ["snapshot", "snapshot", "snapshot", "changed"]


def test_until_change_times_out(monkeypatch):
    events = []
    monkeypatch.setattr(
        gh_pr_watch,
        "collect_snapshot",
        lambda args: (_snapshot(["idle"]), Path("/tmp/s.json")),
    )
    monkeypatch.setattr(
        gh_pr_watch, "print_event", lambda e, p: events.append((e, p))
    )
    clock = iter([0, 0, 40, 80])
    monkeypatch.setattr(gh_pr_watch.time, "monotonic", lambda: next(clock))
    monkeypatch.setattr(gh_pr_watch.time, "sleep", lambda s: None)

    assert gh_pr_watch.run_watch(_watch_args(max_wait=60)) == 0
    assert [e for e, _ in events][-1] == "timeout"


def test_recommend_actions_asks_for_rebase_when_conflicting_or_behind():
    for overrides in ({"mergeable": "CONFLICTING"}, {"merge_state_status": "BEHIND"}):
        pr = sample_pr()
        pr.update(overrides)
        actions = gh_pr_watch.recommend_actions(
            pr, sample_checks(), [], [], [], 0, 3
        )
        assert actions == ["rebase_onto_base"], overrides


def test_behind_pr_is_not_ready_to_merge():
    pr = sample_pr()
    pr["merge_state_status"] = "BEHIND"
    assert not gh_pr_watch.is_pr_ready_to_merge(pr, sample_checks(), [])


def test_budget_spent_stops_watch(monkeypatch):
    events = []
    monkeypatch.setattr(
        gh_pr_watch,
        "collect_snapshot",
        lambda args: (_snapshot(["stop_budget_spent"]), Path("/tmp/s.json")),
    )
    monkeypatch.setattr(
        gh_pr_watch, "print_event", lambda e, p: events.append((e, p))
    )
    assert gh_pr_watch.run_watch(_watch_args()) == 0
    assert [e for e, _ in events] == ["snapshot", "stop"]
