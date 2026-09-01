#!/bin/bash
# PROTOTYPE (#269) — film the mode flip. Runs under `simlock run --`.
set -u
cd /Users/julesseguin/.paseo/worktrees/0jcv8gzd/claude-issue-269
D=B63BDB19-DB83-4FC9-AC91-8B47C442367C
C=~/Library/Developer/CoreSimulator/Devices/$D/data/Containers/Data/Application

xcrun simctl boot "$D" 2>/dev/null
xcrun simctl bootstatus "$D" -b >/dev/null 2>&1
xcrun simctl ui "$D" appearance light >/dev/null 2>&1

rm -rf palette-report/img/flip palette-report/img/flip-contact-sheet.png palette-report/img/unflip-contact-sheet.png
find $C -path '*/tmp/*.png' -delete 2>/dev/null

echo "=== filming the flip ==="
xcodebuild test -project App/Quickie.xcodeproj -scheme Quickie \
  -destination "platform=iOS Simulator,id=$D" CODE_SIGNING_ALLOWED=NO \
  -only-testing:QuickieUITests/PalettePrototypeCaptureTests/testCaptureFlipTimeLapse 2>&1 \
  | grep -E "error:|Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)" | tail -5

mkdir -p palette-report/img/flip
find $C -path '*/tmp/*.png' -exec cp {} palette-report/img/flip/ \; 2>/dev/null
echo "--> $(ls palette-report/img/flip | wc -l | tr -d ' ') frames"
