#!/bin/bash
# SessionStart hook: inject environment-specific guidance about where the
# QuickieUITests XCUITest suite can actually run.
#
# The behavioral rule "always implement UI work, never ask, never skip" lives in
# AGENTS.md because it is environment-independent. This hook owns the orthogonal
# question — "can this machine run the UI tests?" — because only a script that
# executes can see CLAUDE_CODE_REMOTE / uname and answer it truthfully per box.
#
# Cloud/web sessions run on Linux with CLAUDE_CODE_REMOTE=true and have no iOS
# simulator; the developer's Mac has Xcode and can run the suite locally. Stdout
# from a SessionStart hook is added to the session context, so a plain echo is
# all that's needed.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || [ "$(uname -s)" = "Linux" ]; then
  cat <<'EOF'
ENV=CLOUD (Linux). No iOS simulator/runtime exists here, so the App/ Xcode
target and the QuickieUITests XCUITest suite CANNOT be built or run on this
machine. Do not attempt it. Exercise the loop's logic with `cd Core && swift
test`, implement any UI work as normal, and let CI (the "App · XCUITest
(macOS)" job) verify the UI behaviors on every PR.
EOF
else
  cat <<'EOF'
ENV=LOCAL MAC. Xcode is installed, so you CAN build and run the QuickieUITests
XCUITest suite locally to verify UI changes. It is slow (~7 min) and entirely
optional — `cd Core && swift test` remains the fast local loop and CI is the
canonical UI gate. To run the UI suite, mirror ci.yml: pre-boot an iPhone
simulator first (a cold headless boot can fail with "Timed out waiting for AX
loaded notification"), then:
  cd App && xcodebuild test -project Quickie.xcodeproj -scheme Quickie \
    -destination 'platform=iOS Simulator,id=<booted-udid>' CODE_SIGNING_ALLOWED=NO
EOF
fi
