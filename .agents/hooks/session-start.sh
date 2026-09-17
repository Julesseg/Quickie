#!/usr/bin/env bash
set -euo pipefail

[ "${AGENT_REMOTE:-false}" = "true" ] || exit 0

readonly SWIFT_VERSION="6.0.3"
readonly SWIFT_DIR="/opt/swift-${SWIFT_VERSION}"
readonly SWIFT_BIN="${SWIFT_DIR}/usr/bin"
readonly TARBALL_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"

if [ -n "${AGENT_ENV_FILE:-}" ]; then
  printf 'export PATH="%s:$PATH"\n' "$SWIFT_BIN" >> "$AGENT_ENV_FILE"
fi

if [ -x "${SWIFT_BIN}/swift" ]; then
  printf 'Swift %s already present at %s\n' "$SWIFT_VERSION" "$SWIFT_DIR" >&2
  exit 0
fi

{
  printf 'Installing Swift %s runtime dependencies...\n' "$SWIFT_VERSION"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq \
    binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-s1 libncurses-dev \
    libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev \
    pkg-config tzdata zlib1g-dev

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  curl -fsSL -o "${tmp_dir}/swift.tar.gz" "$TARBALL_URL"
  mkdir -p "$SWIFT_DIR"
  tar xzf "${tmp_dir}/swift.tar.gz" -C "$SWIFT_DIR" --strip-components=1
  "${SWIFT_BIN}/swift" --version
} >&2
