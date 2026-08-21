# Keyboard geometry is read in window coordinates, never the screen's

Status: accepted. Refines the manual bar lift of issues #58 and #64 — the two
input channels, the held inset, and the interactive swipe-dismiss are untouched;
only the coordinate space the geometry is measured in, and the classification
built on it, change.

## Context

The launcher lifts its bottom bar onto the keyboard by hand: SwiftUI's automatic
avoidance is off (`.ignoresSafeArea(.keyboard)`) so that a context menu's
transient first-responder resignation cannot reflow the result list, and so that
an interactive swipe-dismiss can move the bar under the finger. `KeyboardBarLift`
holds that policy in QuickieCore, `swift test`-gated.

Its input was the keyboard's overlap of the **screen** bottom:

```swift
overlap: UIScreen.main.bounds.height - endFrame.minY
```

That is true only when the window *is* the display. On iPad it frequently is
not — Split View, Slide Over, Stage Manager, and iPadOS 26 free window resizing
all give the app a window smaller than, and offset within, the screen. The
expression then measures a distance in the display's coordinate space and
applies it as an inset in the window's, so the bar lifts by an amount unrelated
to what the keyboard actually covers: too much for a window that floats clear of
the display bottom, and a full keyboard's height for a window the keyboard never
reaches at all. `UIScreen.main` is deprecated for exactly this reason.

Keyboard *style* compounded it. A floating or split keyboard reports a small
detached frame; subtracting its `minY` from the screen height yields a large,
meaningless lift. And the software-keyboard threshold (120pt, separating a real
keyboard from a hardware keyboard's shortcuts bar) was compared against the
overlap — a value a short window clips — so a full keyboard seen through a
100pt-tall Stage Manager window would have been classified as an accessory bar.

## Decision

**All keyboard geometry is expressed in the host window's coordinate space, and
the policy consumes rects rather than a pre-computed scalar.**

- `KeyboardBarLift.Geometry` carries the keyboard's end-frame, the window's
  bounds, and the window's bottom safe-area inset — read off one window at one
  moment, so the three can never disagree about which window they describe. The
  App builds it inside `KeyboardFrameObserver`, a UIKit view that has the window
  in hand, converting the notification's end-frame with
  `UIWindow.convert(_:from: nil as UIWindow?)` — the documented screen → window
  hop. The old `UIApplication.connectedScenes` key-window walk is gone; it
  guessed at a window in a world where the app may own several.
- `Geometry.coverage` classifies the result as **docked** (as wide as the window
  *and* reaching its bottom edge, covering `overlap` points of it), **undocked**
  (inside the window but detached from the bottom edge — a floating or split
  keyboard), or **away**. Docked with zero overlap is both a dismissal and a
  window floating clear above the keyboard: geometrically the same thing, and
  treated the same. Docking is judged on the keyboard being as *wide as* the
  window rather than covering it corner to corner, because under iPadOS 26 free
  placement a window can hang off a display edge — the display-wide keyboard
  still covers every visible point of its bottom band without ever reaching that
  edge.
- The lift is the docked overlap beyond the bottom safe area. An undocked
  keyboard lifts nothing and **releases** rather than holds, so undocking a
  keyboard that had lifted the bar drops it back to the window bottom.
- `softwareKeyboardThreshold` is re-expressed as `Geometry.isSoftwareKeyboard`,
  read from the keyboard's **own** height rather than its window overlap. Its
  one job is now the hide rule: only a software keyboard's disappearance holds
  the inset (the context-menu case, issue #58); an accessory bar leaving
  releases it, since with a hardware keyboard attached there is no software
  keyboard whose inset is worth preserving.
- A docked keyboard of *any* height lifts the bar by what it covers, so a
  hardware keyboard's shortcuts bar produces the accessory bar's lift — and can
  never leave a full keyboard's inset stranded beneath it.
- The notification's `keyboardIsLocalUserInfoKey` is a **parameter of the
  policy**, not a filter in the App: side by side on iPad, the other app's
  keyboard posts here too, and though it may well cover our window, nothing of
  ours is focused, so it holds. Making it an argument keeps the rule inside the
  `swift test` gate with the rest of the policy.
- The live channel gains a second reason to act. `KeyboardBarLift.live` tracks a
  sample when a list drag is in flight (the interactive swipe-dismiss, unchanged)
  **or when the window itself changed shape** — a Split View divider drag, a
  Stage Manager or iPadOS 26 resize, a rotation. A reshaped window sits over a
  different band of a keyboard that has not moved, and the keyboard posts no
  notification for it, so the layout pass is the only notice; without it the bar
  keeps the inset it had at the window's old size. Both are the user's finger on
  something, so both apply immediately and unanimated.

- **A keyboard that leaves is not self-describing, so the App reports the menu.**
  The held inset of issue #58 exists so a long-press context menu can open over
  a still list: the menu drops the keyboard, and releasing the lift would reflow
  the reversed list out from under the menu the user is reading. But iPad's
  dedicated dismiss key drops the keyboard too, and there the bar must fall to
  the window bottom rather than hang a keyboard's height above nothing.

  The two are indistinguishable at the notification. Traced on iPhone 17 Pro and
  iPad Pro 11" (iOS 26.3), a menu-driven drop and a dismiss-key drop post the
  same end frame, the same duration (0.3833) and curve (7), the same
  `isLocal`, and both fire `willHide`/`didHide`. The text field keeps first
  responder through **both** — the long-standing comment that the menu "resigns
  first responder" is not what happens. Window count, key window, and window
  levels are identical either side.

  So the menu is reported rather than inferred: `ContextMenuPresence` counts the
  menu's own **preview** view appearing and disappearing — SwiftUI builds it when
  the menu displays and tears it down when it dismisses — and
  `View.resultContextMenu`, the single place every menu in the app is built,
  feeds it. `notified` takes `contextMenuOpen` and holds only for that.

## Consequences

- The `KeyboardDismissUITests` class now carries both halves — the dismiss key
  must drop the bar, the long-press must not move it — because they are the same
  notification and only pass together if the menu signal is really being read.
  Each was checked against its own negation: forcing `contextMenuOpen` true
  reproduces the frozen bar exactly (846.0pt before and after).
- Every windowing configuration is one code path: the conversion normalises full
  screen, Split View, Slide Over, and Stage Manager into the same question —
  "how much of *this window's* bottom edge is covered?"
- The bar now re-seats itself *during* a window resize rather than only at the
  keyboard's next move — the behaviour a windowed launcher needs, and the reason
  the live channel had to learn a second cause.
- A hardware keyboard now lifts the bar onto its shortcuts bar instead of
  leaving the bar underneath it. This is a visible change on iPhone too, and the
  intended one: the bar should never sit behind the keyboard's own chrome.
- The policy's test surface grew rects. That is the point — window-smaller-than-
  screen and undocked-keyboard geometries are expressible in `swift test` now,
  where before the only input was a scalar that had already lost the
  information.
- `UIView.keyboardLayoutGuide` keeps `followsUndockedKeyboard` off, so a floating
  or split keyboard reports zero overlap on the live channel — the same answer
  `coverage` gives it. The two channels agree by construction.

## Considered options

- **Adopt `keyboardLayoutGuide` for the notified channel too, with
  `followsUndockedKeyboard`.** Rejected: the guide reports the keyboard's
  *settled* position through layout, not its end-frame at animation start, and
  the bar riding the keyboard's own timing (rather than trailing it) is the
  behaviour issue #58 exists to get. The guide stays the live-drag channel.
- **Keep the scalar overlap and convert in the App.** Rejected: the docked /
  undocked classification, the software-keyboard test, and the is-it-even-our-
  keyboard question are policy, not plumbing, and pre-flattening to a scalar is
  what hid the bug — a single number cannot say whether it came from a keyboard
  that was detached, clipped, or simply short.
- **Use `window.screen.coordinateSpace` for the conversion.** Rejected: it works,
  but it re-introduces a screen reference into the keyboard path for no gain
  over the window-to-window overload, which says what it means.
