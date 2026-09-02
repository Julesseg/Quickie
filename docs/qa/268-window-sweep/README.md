# Odd-size QA sweep — issue #268

Captured on an **iPad Pro 13" (M5), iPadOS 26.3**, in **Windowed Apps** mode
(Settings → Multitasking & Gestures), driving the real window rather than a
stand-in: each shot is the app in a window of the stated size, screenshotted
with `xcrun simctl io … screenshot`.

| Shot | Window | What it shows |
| --- | --- | --- |
| `01-full-screen-portrait-1032pt` | 1032×1376 | Regular width: the [[Readable command column]], input bar centred, margins either side. |
| `02-default-window-880pt` | 880×1376 | The declared `LauncherWindow.defaultSize` width, taken by a fresh window. Still regular, still a column — which is the number's whole job. |
| `03-narrow-window-421pt` | 421×1376 | Compact: the iPhone layout, edge to edge, no column. Nothing clipped, no orphaned margin. |
| `04-narrow-window-375pt` | 375×1376 | The same at Slide Over's neighbourhood — the narrowest window the sweep reached. |
| `05-landscape-empty-state-before` | 1376×1032, keyboard docked | Audit finding F12 as it shipped: the block's ink centres at **200.5pt** in a band whose centre is **235.5pt** — 35pt high. |
| `06-landscape-empty-state-after` | 1376×1032, keyboard docked | The same window after: **237.0pt**, 1.5pt off the band's centre. |

The band in 05/06 is the window's top down to the input bar's glass, measured at
471pt on this window; both shots are the same build settings, same orientation,
same docked keyboard, so the only difference is the composition.

## What this does not cover

**Quadrants and other short windows were not captured here.** iPadOS 26 snaps a
dragged window to sizes of its own choosing and would not take the height drags
reliably, so the sweep walked the *width* axis end to end and reached the height
axis only through the landscape-with-keyboard case above — which is the short
band F12 is about (471pt of usable height), but is not a quadrant.

What covers the rest is `LauncherWindowTests`, which walks the tile table as
geometry on three iPads in both orientations — halves, thirds, quadrants and
Slide Over — and re-runs ADR 0040's keyboard lift at each tile placed where the
system puts it, including an iPad mini's landscape quadrant (372pt tall under a
~353pt keyboard) and a top quadrant the keyboard never reaches at all.
