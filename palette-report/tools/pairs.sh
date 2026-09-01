#!/bin/bash
# PROTOTYPE (#269) — capture the docked/palette pairs with `simctl launch`.
#
# Deliberately not XCUITest: a UI test has to *type* to fill the query, and
# typing raises the software keyboard — the exact condition palette mode is
# defined by the absence of. `-palette-seed-query` fills it at launch instead,
# so every shot here is taken with no keyboard on screen, which is what a
# hardware-keyboard iPad actually looks like.
set -u
cd /Users/julesseguin/.paseo/worktrees/0jcv8gzd/claude-issue-269
D=B63BDB19-DB83-4FC9-AC91-8B47C442367C
BUNDLE=com.julesseguin.quickie
OUT=$PWD/palette-report/img
COMMON="--uitesting -uitest-reset-signals -uitest-instant-motion -uitest-reset-folders -uitest-seed-files -uitest-stub-reminders -uitest-pin-favorite builtin.settings -palette-prototype -palette-badge -palette-force-hardware-keyboard"

shot() { # $1=dir  $2=name  $3=mode  $4=query(optional)
  local dir="$OUT/$1" name=$2 mode=$3 q=${4:-}
  mkdir -p "$dir"
  xcrun simctl terminate $D $BUNDLE >/dev/null 2>&1
  sleep 1
  if [ -n "$q" ]; then
    xcrun simctl launch $D $BUNDLE $COMMON -palette-mode "$mode" -palette-seed-query "$q" >/dev/null 2>&1
  else
    xcrun simctl launch $D $BUNDLE $COMMON -palette-mode "$mode" >/dev/null 2>&1
  fi
  sleep 6
  xcrun simctl io $D screenshot "$dir/$mode-$name.png" >/dev/null 2>&1
  echo "--> $1/$mode-$name.png"
}

capture_set() { # $1 = subdir
  for mode in docked palette; do
    shot "$1" 10-home           "$mode"
    shot "$1" 11-results-ranked "$mode" "se"
    shot "$1" 12-results-calc   "$mode" "2+2"
    shot "$1" 13-results-long   "$mode" "s"
  done
}

echo "=== light pairs ==="
xcrun simctl ui $D appearance light >/dev/null 2>&1
capture_set light

echo "=== dark pairs ==="
xcrun simctl ui $D appearance dark >/dev/null 2>&1
capture_set dark
xcrun simctl ui $D appearance light >/dev/null 2>&1

echo "=== the trigger, unforced (what a simulator can actually reach) ==="
mkdir -p "$OUT/trigger"
xcrun simctl terminate $D $BUNDLE >/dev/null 2>&1; sleep 1
xcrun simctl launch $D $BUNDLE --uitesting -uitest-reset-signals -uitest-instant-motion \
  -uitest-pin-favorite builtin.settings -palette-prototype -palette-badge \
  -palette-seed-query se >/dev/null 2>&1
sleep 6
xcrun simctl io $D screenshot "$OUT/trigger/unforced.png" >/dev/null 2>&1
echo "--> trigger/unforced.png"

xcrun simctl terminate $D $BUNDLE >/dev/null 2>&1; sleep 1
xcrun simctl launch $D $BUNDLE --uitesting -uitest-reset-signals -uitest-instant-motion \
  -uitest-pin-favorite builtin.settings -palette-prototype -palette-badge \
  -palette-force-hardware-keyboard -palette-seed-query se >/dev/null 2>&1
sleep 6
xcrun simctl io $D screenshot "$OUT/trigger/forced.png" >/dev/null 2>&1
echo "--> trigger/forced.png"

echo "=== done ==="
find "$OUT" -name '*.png' | sort
