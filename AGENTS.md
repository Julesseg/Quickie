# Quickie

iOS launcher.

## Agent skills

### Issue tracker

Issues, PRDs, and feature requests are tracked as **GitHub issues** in `Julesseg/Quickie`, managed via the `gh` CLI. External pull requests are also treated as a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five canonical triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) with their default names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Conventions

### Conventional Commits — commit subjects *and* PR titles

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/),
enforced by a `PreToolUse` hook (`.claude/hooks/validate-commit-msg.py`). **PR
titles must match too.** Title PRs `<type>(<scope>)!: <description>` using the
same types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`.

### Always implement the UI part of an issue — never ask

**If an issue requires UI work, implement it. Do not ask whether you should,
and do not skip, defer, or stub it.** The fact that the UI is only verifiable in
CI (not on your local machine) is **never** a reason to leave it out, hand it
back to the user, or ask for permission. Treat "this is only testable by CI" as
a normal, expected condition of working in this repo — not a blocker and not a
question. The correct action is always: write the UI code, push it, and let CI
verify it.

Concretely, **do not** say or ask any of the following:

- "I can't test the UI locally, should I still implement it?" → Yes. Always.
  Implement it without asking.
- "The UI part is only testable in CI, so I'll leave it out / leave it as a
  follow-up." → No. Implement it now, in the same change.
- "Do you want me to implement the UI, or just the logic?" → Both. The UI is
  in scope by default.

Just do the UI work and open the PR. CI is the verification step — that is what
it is for.

#### Why UI tests are CI-only (background, not a decision to revisit)

The `QuickieUITests` XCUITest target runs **only in CI** (the `App · XCUITest
(macOS)` job in `.github/workflows/ci.yml`), never locally as a precondition for
implementing an issue. This is the settled, correct setup — do not treat its
CI-only execution as a gap to fix or a reason to change how you work.

- XCUITest needs an iOS runtime and simulator, which exist only on macOS. CI's
  hosted `macos` runners are the canonical, reproducible environment for them;
  reproducing that locally is unnecessary and platform-bound.
- The loop's logic lives in `QuickieCore`, a pure SwiftPM package whose behavior
  suite (`cd Core && swift test`) runs anywhere — that is what you exercise while
  implementing. The UI target is a thin acceptance layer on top, best verified by
  CI on every PR.
- Keeping the UI tests CI-only keeps local iteration fast and platform-agnostic
  while still gating every PR on the full UI acceptance criteria.

When implementing an issue: write the UI code, rely on `swift test` for the logic
locally, and let the CI XCUITest job cover the UI behaviors. That split is by
design — it does not change the rule above: the UI always gets implemented.
