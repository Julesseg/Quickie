# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker. This repo uses the canonical names unchanged.

| Canonical role   | Label in this repo | Meaning                                  | Exists |
| ---------------- | ------------------ | ---------------------------------------- | ------ |
| `needs-triage`   | `needs-triage`     | Maintainer needs to evaluate this issue  | yes    |
| `needs-info`     | `needs-info`       | Waiting on reporter for more information | **no** |
| `ready-for-agent`| `ready-for-agent`  | Fully specified, ready for an AFK agent  | yes    |
| `ready-for-human`| `ready-for-human`  | Requires human implementation            | yes    |
| `wontfix`        | `wontfix`          | Will not be actioned                     | yes    |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

`needs-info` has never been created in the repo, so `gh issue edit --add-label needs-info` fails. Create it on first use:

```sh
gh label create needs-info --description "Waiting on reporter for more information" --color D4C5F9
```

## Non-triage labels

`agent-dispatched` is **not** a triage role — it is the idempotency guard the
auto-dispatch workflow applies so an issue is only ever handed to one agent
session. Don't set or clear it by hand during triage. See
[`auto-dispatch.md`](auto-dispatch.md).
