# The system's edge effect under the status bar

Status: accepted. Amends the status-bar half of ADR 0043: a row under the status
bar is no longer drawn in full. The Favorites-grid half of 0043 stands — nothing
is painted between the cards and the rows behind them.

## Context

ADR 0043 took the blur bands off the launcher's lists and left a row scrolling
under the status bar drawn as itself. In use, that puts the clock, the Dynamic
Island's flanks and the signal and battery glyphs straight on top of a row's
title and icon, and both turn unreadable.

0043 ruled out "a veil", and rightly: its bands were ours — a
`.ultraThinMaterial` rectangle with a hand-drawn gradient mask, one more surface
the design did not ask for. iOS 26 has its own answer to exactly this
collision: the **scroll edge effect** (`UIScrollView.topEdgeEffect`, SwiftUI's
`scrollEdgeEffectStyle`), which softens and dims a scroll view's content where
system chrome overlays its edge. It is the platform's behavior, the one every
other iOS 26 app shows under its bars, and ADR 0010's never-hand-roll-blur rule
points at it rather than away from it.

## Decision

**The launcher's two lists — Home's Recent list and the [[Result list]] — wear
the system's soft top edge effect under the status bar.** One modifier,
`statusBarEdgeEffect()`, applies it to both, so a Recent row and a result row
still leave the screen the same way.

The style alone draws nothing on these surfaces. The effect is shaped by the
elements of a bar overlaying the scroll view's edge (`safeAreaBar`, or UIKit's
`UIScrollEdgeElementContainerInteraction`), and the launcher wears no bar — its
navigation bar is hidden. So the modifier registers a 1pt `safeAreaBar` at the
status bar's lower edge: near-transparent (a `Color.clear` does not render, so
it registers no element and the effect never appears), and taking no touches.
The effect then covers the status area and fades out just below it.

It stops at the status bar. The Favorites grid is not a bar and gets no effect
under it; the cards stay on the backdrop as 0043 left them.

## Consequences

- A row under the status bar is blurred and dimmed by the system, not drawn in
  full. It comes back into focus as it scrolls down out of the status area.
- The lists' top content inset grows by the 1pt bar. The Result list takes the
  effect outside its `GeometryReader`, so the viewport the stack is pinned to
  already excludes that point and the pin is unchanged.
- The breadcrumb surfaces (a [[Quick capture]]'s choice list, the [[Search Files
  context]]) keep their own progressive-blur bands, which carry chrome; they
  do not also take this effect.
- If a later iOS draws the edge effect under the status bar with no bar present,
  the hairline bar becomes redundant and can go; the style stays.
