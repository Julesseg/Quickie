---
name: ui-report
description: "Build a single-file HTML report with screenshots of every screen a change touched, so the reviewer checks UI work without launching the app. Use after implementing anything a user sees, or when asked for screenshots or a visual report of a change."
---

# UI report

One HTML file the reviewer opens to see the change on screen: every screen
and state the diff touched, captured from the built app, each with a caption
saying what it shows and which requirement it demonstrates. The report is
complete when every touched screen is in it, or listed under "Not captured"
with the reason.

## 1. List the shots

From the diff against the base branch, list every screen the change adds
or alters, and for each the states worth seeing: the states the change
introduces (empty, populated, error, in progress), light and dark when
colours or assets changed, and each device family the app ships for. Pair
each shot with the acceptance criterion or issue line it demonstrates. Write
this list down first: it is the report's table of contents and the bar for
step 2.

## 2. Capture

Build the branch and drive the app to each listed state, saving one PNG per
shot. Take the project's own route when it has one (a screenshot test
target, a UI-test helper, a storybook, a `scripts/` entry), reusing its
fixtures and launch environment to reach states; otherwise follow the
platform recipe in `references/capture.md`. Record, per shot, the device,
appearance, and how the state was reached. A state you cannot reach goes on
the "Not captured" list with what blocked it, and the capture continues.

## 3. Build the file

Write a manifest (shape documented at the top of the script) and run:

```sh
python3 <this skill's dir>/scripts/build_report.py manifest.json --out <path>
```

Default path: `~/.local/share/ui-reports/<repo>/<branch>/<UTC timestamp>.html`.
The output inlines the images, so it is one file that outlives the worktree.
Open it once and confirm every listed shot renders.

## 4. Hand it over

Put the report path in the final message and wherever the work is reported
(the PR body, when there is a PR). The file lives on this machine, so say so.
