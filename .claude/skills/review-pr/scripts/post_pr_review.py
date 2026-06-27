#!/usr/bin/env python3
"""Post a code review with inline comments to a GitHub PR via the gh CLI.

Reads a findings JSON file and submits a single PR review containing an
overall summary plus inline comments anchored to specific lines. Posting one
review (rather than many separate comments) keeps the PR timeline tidy and
lets the author resolve the feedback as a unit.

findings JSON shape:
{
  "summary": "Overall review text (markdown ok).",
  "event": "COMMENT",                 # COMMENT | REQUEST_CHANGES | APPROVE
  "comments": [
    {"path": "src/app.py", "line": 42, "body": "..."},
    {"path": "src/app.py", "start_line": 10, "line": 15, "body": "range comment"}
  ]
}

Inline comments must point at lines present in the PR diff, or GitHub rejects
the whole review. If the full post fails, this script falls back to posting the
summary alone (with the inline findings folded into the body) so the review
still lands, and reports which comments could not be anchored.
"""
import argparse
import json
import subprocess
import sys


def run_gh(args, **kwargs):
    return subprocess.run(["gh"] + args, capture_output=True, text=True, **kwargs)


def resolve_repo():
    out = run_gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"])
    if out.returncode != 0:
        sys.exit(f"Could not resolve repo via gh: {out.stderr.strip()}")
    return out.stdout.strip()


def post_review(repo, pr, payload):
    return run_gh(
        ["api", "--method", "POST", f"repos/{repo}/pulls/{pr}/reviews", "--input", "-"],
        input=json.dumps(payload),
    )


def main():
    ap = argparse.ArgumentParser(description="Post a PR review with inline comments.")
    ap.add_argument("--pr", required=True, help="PR number")
    ap.add_argument("--findings", required=True, help="Path to findings JSON file")
    ap.add_argument("--repo", default=None, help="owner/name (auto-detected if omitted)")
    ap.add_argument("--dry-run", action="store_true", help="Print the payload, don't post")
    args = ap.parse_args()

    with open(args.findings) as f:
        findings = json.load(f)

    summary = findings.get("summary", "")
    event = findings.get("event", "COMMENT")
    comments = findings.get("comments", [])

    payload = {"body": summary, "event": event}
    if comments:
        payload["comments"] = []
        for c in comments:
            entry = dict(c)
            entry.setdefault("side", "RIGHT")
            payload["comments"].append(entry)

    if args.dry_run:
        print(json.dumps(payload, indent=2))
        return

    repo = args.repo or resolve_repo()

    proc = post_review(repo, args.pr, payload)
    if proc.returncode == 0:
        n = len(comments)
        print(f"Posted review to {repo}#{args.pr} with {n} inline comment(s).")
        return

    # Most common failure: an inline comment points at a line not in the diff,
    # which makes GitHub 422 the entire review. Fall back to summary-only so the
    # feedback still lands, with the inline points folded into the body.
    sys.stderr.write(f"Inline review failed: {proc.stderr.strip()}\n")
    if not comments:
        sys.exit(1)

    folded = summary + "\n\n---\n\n### Inline findings (could not anchor to diff lines)\n"
    for c in comments:
        loc = f"{c.get('path', '?')}:{c.get('line', '?')}"
        folded += f"\n- **{loc}** — {c.get('body', '')}"

    proc2 = post_review(repo, args.pr, {"body": folded, "event": event})
    if proc2.returncode == 0:
        print(
            f"Posted summary-only review to {repo}#{args.pr} "
            "(inline anchoring failed; findings folded into the body)."
        )
    else:
        sys.stderr.write(f"Summary post also failed: {proc2.stderr.strip()}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
