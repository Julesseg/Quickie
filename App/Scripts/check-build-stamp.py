#!/usr/bin/env python3
"""Guard the build stamp's wiring in Quickie.xcodeproj against silent drift.

The stamp (CONTEXT.md -> Build stamp) is only trustworthy if
`Scripts/stamp-git-commit.sh` runs on *every* build of the app target and runs
*last*. Every one of those conditions lives in project.pbxproj, where an
unrelated Xcode edit can quietly drop or reorder a build phase — and the damage
is invisible: the app still builds, still shows a stamp, and the stamp is simply
wrong. A device would report a commit it was not built from.

So this checks the four properties that make the stamp correct:

  1. The `Stamp git commit` shell-script phase exists and invokes the script.
  2. The Quickie app target lists it, and lists it LAST — after the plist is
     processed into the product, before Xcode's final code-signing step.
  3. It is `alwaysOutOfDate = 1`, so incremental builds re-stamp. Without this,
     Xcode skips the phase when its (empty) inputs haven't changed, and a build
     made after switching commits keeps the old hash.
  4. `ENABLE_USER_SCRIPT_SANDBOXING = NO` on both of the app target's build
     configurations — the script reads .git and writes into the product, and
     the sandbox denies both.

Pure stdlib, no Xcode required, so it runs on a Linux CI runner. Text-matching
against the pbxproj rather than parsing it: the file is generated in a stable
format, and a parser is far more code than the four assertions are worth.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "Quickie.xcodeproj" / "project.pbxproj"
SCRIPT = ROOT / "Scripts" / "stamp-git-commit.sh"

PHASE_NAME = "Stamp git commit"

failures = []


def fail(message):
    failures.append(message)


text = PBXPROJ.read_text()

if not SCRIPT.exists():
    fail(f"{SCRIPT.relative_to(ROOT)} is missing — the stamp phase invokes it")
elif SCRIPT.stat().st_mode & 0o111 == 0:
    fail(f"{SCRIPT.relative_to(ROOT)} is not executable")

# 1. The phase object itself, and 3. its always-out-of-date flag.
phase = re.search(
    r"(\w+) /\* " + re.escape(PHASE_NAME) + r" \*/ = \{\n(.*?)\n\t\t\};",
    text,
    re.DOTALL,
)
if not phase:
    fail(f"no '{PHASE_NAME}' shell-script build phase in project.pbxproj")
else:
    phase_id, body = phase.group(1), phase.group(2)

    if "isa = PBXShellScriptBuildPhase;" not in body:
        fail(f"'{PHASE_NAME}' is not a PBXShellScriptBuildPhase")

    if "stamp-git-commit.sh" not in body:
        fail(f"'{PHASE_NAME}' no longer invokes Scripts/stamp-git-commit.sh")

    if "alwaysOutOfDate = 1;" not in body:
        fail(
            f"'{PHASE_NAME}' must set alwaysOutOfDate = 1 (Xcode: uncheck "
            '"Based on dependency analysis") or incremental builds will keep a '
            "stale commit in the Info.plist"
        )

    # 2. The app target must run it, last.
    target = re.search(
        r"/\* Quickie \*/ = \{\n\t\t\tisa = PBXNativeTarget;.*?buildPhases = \(\n(.*?)\n\t\t\t\);",
        text,
        re.DOTALL,
    )
    if not target:
        fail("could not find the Quickie app target's buildPhases list")
    else:
        phases = [line.strip().rstrip(",") for line in target.group(1).splitlines()]
        ids = [p.split(" ")[0] for p in phases]
        if phase_id not in ids:
            fail(f"the Quickie app target does not run the '{PHASE_NAME}' phase")
        elif ids[-1] != phase_id:
            fail(
                f"'{PHASE_NAME}' must be the LAST build phase of the Quickie "
                f"target (it writes into the built Info.plist); phases are: "
                f"{', '.join(phases)}"
            )

# 4. Sandboxing off on both of the app target's configurations. They are the
#    only ones carrying `INFOPLIST_FILE = Info.plist` (the extensions point at
#    their own), which makes that a reliable way to pick them out.
app_configs = re.findall(
    r"buildSettings = \{\n(.*?)\n\t\t\t\};", text, re.DOTALL
)
app_configs = [c for c in app_configs if "INFOPLIST_FILE = Info.plist;" in c]
if len(app_configs) != 2:
    fail(
        f"expected 2 app-target build configurations (Debug/Release), found "
        f"{len(app_configs)} — update this check"
    )
for config in app_configs:
    if "ENABLE_USER_SCRIPT_SANDBOXING = NO;" not in config:
        name = re.search(r"PRODUCT_NAME = (.*?);", config)
        fail(
            "the app target needs ENABLE_USER_SCRIPT_SANDBOXING = NO in both "
            "Debug and Release; the stamp script reads .git and writes into "
            f"the built product (config for {name.group(1) if name else '?'})"
        )

if failures:
    print("Build stamp wiring is broken:\n", file=sys.stderr)
    for message in failures:
        print(f"  - {message}", file=sys.stderr)
    print(
        "\nSee App/Scripts/stamp-git-commit.sh and CONTEXT.md -> Build stamp.",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"Build stamp wiring OK: '{PHASE_NAME}' runs last on every app build.")
