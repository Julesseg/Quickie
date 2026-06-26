#!/bin/bash
# SessionStart hook: install a Swift toolchain so QuickieCore's tests are
# runnable in fresh Claude Code on the web containers (which ship without Swift).
#
# Only the `Core/` package is built/tested here — it depends solely on
# Foundation + Swift Testing, both available in the Linux toolchain. The iOS
# app target (`App/`) needs SwiftUI/SwiftData/UIKit and therefore Xcode on a
# Mac; it cannot be compiled on Linux and this hook does not try.
#
# Progress goes to stderr; stdout carries a single JSON object whose
# additionalContext tells the session how to run the tests.
set -euo pipefail

# Local (non-web) sessions use the developer's own Xcode/Swift — do nothing.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SWIFT_VERSION="6.0.3"
SWIFT_DIR="/opt/swift-${SWIFT_VERSION}"
SWIFT_BIN="${SWIFT_DIR}/usr/bin"
TARBALL_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"

# Put swift on PATH for the rest of the session (idempotent across re-runs).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${SWIFT_BIN}:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

emit_context() {
  # Single JSON object on stdout → injected into the session as context.
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Swift ${SWIFT_VERSION} is installed at ${SWIFT_BIN} (also on PATH). Run the QuickieCore tests with: cd Core && swift test. NOTE: only the Core/ SwiftPM package builds on Linux; the App/ iOS target needs Xcode on a Mac and cannot be compiled here."}}
JSON
}

# Idempotent: if the toolchain is already extracted, just re-export PATH + context.
if [ -x "${SWIFT_BIN}/swift" ]; then
  echo "Swift ${SWIFT_VERSION} already present at ${SWIFT_DIR}" >&2
  emit_context
  exit 0
fi

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
  echo "Swift ${SWIFT_VERSION} ready."
} >&2

emit_context
