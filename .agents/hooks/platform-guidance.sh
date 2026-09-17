#!/usr/bin/env bash
set -euo pipefail

if [ "${AGENT_REMOTE:-false}" = "true" ]; then
  cat <<'EOF'
ENV=REMOTE LINUX. No iOS simulator/runtime exists here, so the App/ Xcode
target and the QuickieUITests XCUITest suite cannot run on this machine. Exercise
the portable logic with `cd Core && swift test`, implement UI work normally,
and let the `App · XCUITest (macOS)` CI job verify UI behavior.
EOF
elif [ "$(uname -s)" = "Linux" ]; then
  cat <<'EOF'
ENV=LOCAL LINUX. No Xcode or iOS simulator exists here, so the App/ target and
the QuickieUITests XCUITest suite cannot run on this machine. Implement UI work
normally and let CI verify it.
EOF
  if command -v swift >/dev/null 2>&1 || [ -x "$HOME/.local/share/swiftly/bin/swift" ]; then
    printf '%s\n' 'A Swift toolchain is available. Run the portable tests with `cd Core && swift test`.'
  else
    printf '%s\n' 'No Swift toolchain was found. Report that local Core tests could not run; CI still runs them.'
  fi
else
  cat <<'EOF'
ENV=LOCAL MAC. Xcode is available, so UI tests can run locally when useful.
`cd Core && swift test` remains the fast loop and CI is the full UI gate. For
UI tests, boot a simulator you own, then run:
  cd App && xcodebuild test -project Quickie.xcodeproj -scheme Quickie \
    -destination 'platform=iOS Simulator,id=<booted-udid>' CODE_SIGNING_ALLOWED=NO
Shut down any simulator you booted when verification finishes.
EOF
fi
