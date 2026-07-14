#!/usr/bin/env python3
"""Fail if a generated brand asset or a hand-copied brand constant drifted.

The brand pipeline has two seams its generators cannot police themselves,
both flagged in PR #169 review:

  1. The checked-in vector outputs can go stale or get hand-edited — someone
     tweaks a generator (or the SVG directly) without regenerating. Checked
     by byte-comparing docs/brand/app-icon.svg and the QuickieMark symbolset
     SVG against what the generators emit right now. (The icon's PNG renders
     need Chromium, so only the vector sources are checked.)
  2. QuickieGlyph.swift hand-copies make-app-icon.py's LAVENDER / BG_TOP /
     BG_BOTTOM as SwiftUI Color literals (Swift can't read the Python
     constants); nothing else would catch the two files drifting apart.

Also re-parses the emitted symbolset as XML: Control Center's out-of-process
renderer draws a malformed template as an *empty* glyph, the least visible
possible failure.

Pure stdlib, no rendering. Run from anywhere:

    python3 docs/brand/check-brand-assets.py

CI runs this on every full run (see the brand-assets job in ci.yml). A
docs/**-only push skips CI wholesale (paths-ignore), so a generator edit that
forgets to regenerate is caught on the next full run, not necessarily its own.
"""

import importlib.util
import re
import sys
import xml.dom.minidom
from pathlib import Path

BRAND = Path(__file__).resolve().parent
REPO = BRAND.parents[1]
GLYPH_SWIFT = REPO / "App/QuickieWidgets/QuickieGlyph.swift"


def load(stem):
    """Import a generator script by filename (their names aren't identifiers)."""
    spec = importlib.util.spec_from_file_location(stem.replace("-", "_"), BRAND / f"{stem}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    icon = load("make-app-icon")
    mark = load("make-quickie-mark")
    failures = []

    if icon.SVG_OUT.read_text() != icon.HEADER + icon.build_svg("light"):
        failures.append(f"{icon.SVG_OUT.relative_to(REPO)} is stale or hand-edited "
                        "— rerun docs/brand/make-app-icon.py")

    emitted = mark.build()
    xml.dom.minidom.parseString(emitted)
    if mark.OUT.read_text() != emitted:
        failures.append(f"{mark.OUT.relative_to(REPO)} is stale or hand-edited "
                        "— rerun docs/brand/make-quickie-mark.py")

    # QuickieGlyph's RGB literals in declaration order: `gradient`'s lavender,
    # then `backdrop`'s two purples (its white and the gradient directions have
    # no Python counterpart to drift from).
    swift = GLYPH_SWIFT.read_text()
    found = [tuple(int(v) for v in m) for m in re.findall(
        r"Color\(red: (\d+) / 255, green: (\d+) / 255, blue: (\d+) / 255\)", swift)]

    def rgb(hex_color):
        return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))

    expected = [icon.LAVENDER, rgb(icon.BG_TOP), rgb(icon.BG_BOTTOM)]
    if found != expected:
        failures.append(f"{GLYPH_SWIFT.relative_to(REPO)} color literals {found} no longer "
                        f"match make-app-icon.py's LAVENDER/BG_TOP/BG_BOTTOM {expected}")

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    if failures:
        sys.exit(1)
    print("brand assets in sync")


if __name__ == "__main__":
    main()
