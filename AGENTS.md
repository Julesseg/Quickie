# Quickie

iOS launcher.

## Agent skills

### Issue tracker

Issues, PRDs, and feature requests are tracked as **GitHub issues** in `Julesseg/Quickie`, managed via the `gh` CLI. External pull requests are also treated as a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five canonical triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) with their default names. See `docs/agents/triage-labels.md`.

### Auto-dispatch of unblocked issues

When an issue closes as completed, `unblock-dispatch.yml` finds `ready-for-agent`
issues whose `## Blocked by` list is now fully closed and spawns a Paseo agent
session for each on the self-hosted Mac runner (capped, guarded by the
`agent-dispatched` label). See `docs/agents/auto-dispatch.md`.

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
and do not skip, defer, or stub it.** The fact that you may not be able to run
the UI tests on the box you are on (cloud/web sessions cannot — see below) is
**never** a reason to leave it out, hand it back to the user, or ask for
permission. Treat "CI is the gate for this" as a normal, expected condition of
working in this repo — not a blocker and not a question. The correct action is
always: write the UI code, push it, and let CI verify it.

Concretely, **do not** say or ask any of the following:

- "I can't test the UI locally, should I still implement it?" → Yes. Always.
  Implement it without asking.
- "The UI part is only testable in CI, so I'll leave it out / leave it as a
  follow-up." → No. Implement it now, in the same change.
- "Do you want me to implement the UI, or just the logic?" → Both. The UI is
  in scope by default.

Just do the UI work and open the PR. CI is the verification step — that is what
it is for.

#### CI is the canonical UI gate (background, not a decision to revisit)

The `App · XCUITest (macOS)` job in `.github/workflows/ci.yml` is the canonical,
reproducible gate for the `QuickieUITests` suite, and it runs on every PR. You
**never** need to run the UI suite locally as a precondition for implementing an
issue. This is the settled, correct setup — do not treat it as a gap to fix.

- The loop's logic lives in `QuickieCore`, a pure SwiftPM package whose behavior
  suite (`cd Core && swift test`) runs on any platform — that is what you
  exercise while implementing. The UI target is a thin acceptance layer on top,
  best verified by CI on every PR.
- Whether the box you are on can run the UI suite at all is **environment-
  specific**, so it is not stated here as a flat fact — a `SessionStart` hook
  (`.claude/hooks/platform-guidance.sh`) reports it per session: cloud/web
  sessions run on Linux with no iOS simulator and cannot build the `App/` target
  or run XCUITest; a developer's Mac has Xcode and *can* run the suite locally,
  though doing so is slow and optional. Follow whatever that hook tells you.

When implementing an issue: write the UI code, rely on `swift test` for the logic,
and let the CI XCUITest job cover the UI behaviors. That split is by design — it
does not change the rule above: the UI always gets implemented.

### Never ask to schedule a routine PR check-in

Re-polling a PR you're watching — its CI status, mergeability, or a conflict
transition webhooks don't deliver — is expected, low-stakes background work.
**Do not surface a permission prompt for it.** Never call `send_later` (or any
scheduling tool) just to arm a simple "re-check PR #N later" self-reminder, and
never ask the user whether you should. Rely on the webhook events you're already
subscribed to; if you genuinely need to poll for something webhooks miss, do it
inline when a later turn naturally occurs rather than scheduling a wake-up. The
one exception is when the user has explicitly asked you to schedule something.
