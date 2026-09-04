#!/bin/bash
# PROTOTYPE (#286) — photograph every row × hero combination with `simctl launch`
# + `simctl io screenshot`, on an iPhone and an iPad, light and dark.
#
# Usage: capture.sh <udid> <iphone|ipad>   (run one per device, in parallel)
# Writes row-material-report/img/<device>/<appearance>/<row>-<hero>-<state>.png
set -u
cd "$(dirname "$0")/../.."
D=$1; dev=$2
BUNDLE=com.julesseguin.quickie
OUT=$PWD/row-material-report/img
# `-uitest-instant-motion` is deliberately NOT passed: the hero must settle the
# way it ships (the swing ends ~2s after the last change; we wait 7s).
COMMON="--uitesting -uitest-reset-signals -uitest-reset-folders -uitest-seed-files -uitest-stub-reminders
  -uitest-pin-favorite builtin.settings -uitest-pin-favorite seed.web-search
  -uitest-seed-frecent builtin.settings -uitest-seed-frecent seed.web-search -uitest-seed-frecent builtin.custom-actions-page
  -uitest-seed-frecent builtin.snippets-library -uitest-seed-frecent builtin.system.open-ios-settings
  -proto-no-badge"

shot() { # $1=udid $2=device $3=appearance $4=row $5=hero $6=state $7=query(optional)
  local D=$1 dev=$2 app=$3 row=$4 hero=$5 state=$6 q=${7:-}
  local dir="$OUT/$dev/$app"; mkdir -p "$dir"
  local file="$dir/$row-$hero-$state.png"
  [ -f "$file" ] && { echo "skip $file"; return; }
  xcrun simctl terminate "$D" $BUNDLE >/dev/null 2>&1; sleep 1
  if [ -n "$q" ]; then
    xcrun simctl launch "$D" $BUNDLE $COMMON -proto-row "$row" -proto-hero "$hero" -proto-seed-query "$q" >/dev/null 2>&1
  else
    xcrun simctl launch "$D" $BUNDLE $COMMON -proto-row "$row" -proto-hero "$hero" >/dev/null 2>&1
  fi
  sleep 7
  xcrun simctl io "$D" screenshot "$file" >/dev/null 2>&1
  echo "--> ${file#$OUT/}"
}

{
  for app in light dark; do
    xcrun simctl ui "$D" appearance $app >/dev/null 2>&1
    # The row matrix: every row treatment, hero held at (i), all four states.
    for row in bare flat material; do
      shot "$D" $dev $app $row fill home
      shot "$D" $dev $app $row fill ranked "se"
      shot "$D" $dev $app $row fill long   "s"
      shot "$D" $dev $app $row fill calc   "2+2"
    done
    # The hero matrix: every hero treatment on every row treatment, ranked list.
    for row in bare flat material; do
      for hero in ring strong; do
        shot "$D" $dev $app $row $hero ranked "se"
      done
    done
  done
  xcrun simctl ui "$D" appearance light >/dev/null 2>&1
  xcrun simctl terminate "$D" $BUNDLE >/dev/null 2>&1
}
echo "=== done: $(find "$OUT" -name '*.png' | wc -l) shots ==="
