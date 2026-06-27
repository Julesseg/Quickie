#!/bin/bash
# SessionStart hook: install a Swift toolchain so QuickieCore's tests are
# runnable in fresh Claude Code on the web containers (which ship without Swift).
#
# Only the `Core/` package is built/tested here — it depends solely on
# Foundation + Swift Testing, both available in the Linux toolchain. The iOS
# app target (`App/`) needs SwiftUI/SwiftData/UIKit and therefore Xcode on a
# Mac; it cannot be compiled on Linux and this hook does not try.
#
# Runs ASYNC: the session starts immediately and the toolchain installs in the
# background. Trade-off: a `swift test` issued in the first ~1–2 minutes of a
# brand-new container may briefly race the install (`swift: command not found`)
# — just retry once it finishes. On already-warmed containers it's instant.
set -euo pipefail

# Local (non-web) sessions use the developer's own Xcode/Swift — do nothing.
# Exit before the async directive so local sessions stay a plain no-op.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Tell the harness to run the rest of this script in the background.
echo '{"async": true, "asyncTimeout": 300000}'

SWIFT_VERSION="6.0.3"
SWIFT_DIR="/opt/swift-${SWIFT_VERSION}"
SWIFT_BIN="${SWIFT_DIR}/usr/bin"
TARBALL_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"

# Put swift on PATH for the session as early as possible, so it resolves the
# moment the background install finishes (idempotent across re-runs).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${SWIFT_BIN}:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Idempotent: if the toolchain is already extracted, nothing to do.
if [ -x "${SWIFT_BIN}/swift" ]; then
  echo "Swift ${SWIFT_VERSION} already present at ${SWIFT_DIR}" >&2
  exit 0
fi

# All progress to stderr; stdout already carried the async directive.
{
  echo "Installing Swift ${SWIFT_VERSION} runtime dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq \
    binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-s1 libncurses-dev \
    libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev \
    pkg-config tzdata zlib1g-dev

  echo "Downloading Swift ${SWIFT_VERSION} toolchain (~750 MB)..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  curl -fsSL -o "${TMP}/swift.tar.gz" "${TARBALL_URL}"

  echo "Extracting to ${SWIFT_DIR}..."
  mkdir -p "${SWIFT_DIR}"
  tar xzf "${TMP}/swift.tar.gz" -C "${SWIFT_DIR}" --strip-components=1

  "${SWIFT_BIN}/swift" --version
  echo "Swift ${SWIFT_VERSION} ready. Run tests with: cd Core && swift test"
} >&2
