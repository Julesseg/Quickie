#!/bin/sh
#
# Stamps the short git commit hash of the working tree into the *built* app's
# Info.plist under the `GitCommit` key, so Settings can show exactly which build
# is installed on a device (see BuildInfo.swift).
#
# Correctness rests on three things, all of which check-build-stamp.py enforces
# so they cannot be silently undone:
#
#   1. The phase is LAST in the Quickie target's build phases, so it writes
#      after the Info.plist is processed into the product (an earlier write
#      would be overwritten) and before Xcode's final code-signing step (a
#      later write would break the signature).
#   2. It is marked "always out of date", so it re-runs on EVERY build. An
#      incremental build that recompiles one Swift file still re-stamps —
#      otherwise switching commits without touching a source file would ship a
#      binary labelled with the previous commit.
#   3. User script sandboxing is off for this target, since the script both
#      reads the repo's git metadata and writes into the built product.
#
# The key is written unconditionally — an unreadable git checkout stamps
# `unknown` rather than exiting early. Exiting early would leave whatever the
# *previous* build wrote sitting in the incrementally-reused plist, which is the
# one outcome worse than no stamp at all: a confidently wrong commit.

set -e

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

COMMIT=$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null) || COMMIT=""

if [ -n "${COMMIT}" ]; then
	# A dirty working tree is a different build from the commit it sits on; mark
	# it so a hash read off a device is never mistaken for the pushed commit.
	if ! git -C "${SRCROOT}" diff --quiet HEAD 2>/dev/null; then
		COMMIT="${COMMIT}+"
	fi
else
	COMMIT="unknown"
fi

if [ ! -f "${PLIST}" ]; then
	echo "error: no Info.plist at ${PLIST} — the stamp phase must run after the plist is processed into the product" >&2
	exit 1
fi

/usr/libexec/PlistBuddy -c "Set :GitCommit ${COMMIT}" "${PLIST}" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Add :GitCommit string ${COMMIT}" "${PLIST}"

echo "note: stamped GitCommit = ${COMMIT}"
