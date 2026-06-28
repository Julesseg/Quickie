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

### Conventional Commits — for commit subjects *and* PR titles

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/)
and are enforced deterministically by a `PreToolUse` hook
(`.claude/hooks/validate-commit-msg.py`), which blocks any `git commit` whose
subject doesn't match.

**Pull request titles must follow the exact same convention.** A PR is
squash-merged, so its title becomes the commit subject that lands on `master` —
a non-conforming title silently breaks the history the commit hook protects.
When opening a PR, title it `<type>(<optional scope>)<optional !>: <description>`
using the same allowed types as commits: `feat`, `fix`, `docs`, `style`,
`refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Examples:

- `feat(launcher): add widget grid`
- `fix: correct icon padding`
- `docs: update README`
- `feat!: drop iOS 16 support`

### UI tests run in CI only — this is intentional

The `QuickieUITests` XCUITest target runs **only in CI** (the `App · XCUITest
(macOS)` job in `.github/workflows/ci.yml`), never locally as a precondition for
implementing an issue. This is the settled, correct way to proceed — do not ask
whether UI tests should run locally or treat their CI-only execution as a gap to
fix when starting work.

Why this is the right approach:

- XCUITest needs an iOS runtime and simulator, which exist only on macOS. CI's
  hosted `macos` runners are the canonical, reproducible environment for them;
  reproducing that locally is unnecessary and platform-bound.
- The loop's logic lives in `QuickieCore`, a pure SwiftPM package whose behavior
  suite (`cd Core && swift test`) runs anywhere — that is what you exercise while
  implementing. The UI target is a thin acceptance layer on top, best verified by
  CI on every PR.
- Keeping the UI tests CI-only keeps local iteration fast and platform-agnostic
  while still gating every PR on the full UI acceptance criteria.

When implementing an issue: rely on `swift test` for the logic locally, and let
the CI XCUITest job cover the UI behaviors. That split is by design.
