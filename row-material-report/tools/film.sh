#!/bin/bash
# PROTOTYPE (#286) — film the hero settling after typing, one clip per hero
# treatment on the given row treatment. `-proto-autotype se` types the query
# one character every 220ms starting 2s after launch, so the clip shows the
# hero slot change hands and the light settle.
#
# Usage: film.sh <udid> <iphone|ipad> <row>
set -u
cd "$(dirname "$0")/../.."
D=$1; dev=$2; row=$3
BUNDLE=com.julesseguin.quickie
OUT=$PWD/row-material-report/video; mkdir -p "$OUT"
COMMON="--uitesting -uitest-reset-signals -uitest-pin-favorite builtin.settings -uitest-seed-frecent builtin.settings -uitest-seed-frecent seed.web-search -proto-no-badge"
xcrun simctl ui "$D" appearance dark >/dev/null 2>&1
for hero in fill ring strong; do
  xcrun simctl terminate "$D" $BUNDLE >/dev/null 2>&1; sleep 1
  raw="$OUT/$dev-$row-$hero-raw.mp4"; rm -f "$raw"
  xcrun simctl io "$D" recordVideo --codec h264 --force "$raw" >/dev/null 2>&1 &
  REC=$!
  sleep 2
  xcrun simctl launch "$D" $BUNDLE $COMMON -proto-row "$row" -proto-hero "$hero" -proto-autotype "settings" >/dev/null 2>&1
  sleep 8
  kill -INT $REC; wait $REC 2>/dev/null
  # Trim to the typing + settle, halve the size, and pull a frame strip.
  ffmpeg -y -loglevel error -ss 3 -t 6 -i "$raw" -vf "scale=trunc(iw/4)*2:trunc(ih/4)*2" -an "$OUT/$dev-$row-$hero.mp4"
  ffmpeg -y -loglevel error -ss 3 -t 6 -i "$raw" -vf "fps=4,scale=iw/4:ih/4,tile=12x2" -update 1 "$OUT/$dev-$row-$hero-strip.jpg"
  rm -f "$raw"
  echo "--> $dev-$row-$hero.mp4"
done
xcrun simctl terminate "$D" $BUNDLE >/dev/null 2>&1
