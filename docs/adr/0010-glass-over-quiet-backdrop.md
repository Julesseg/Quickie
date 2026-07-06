# Liquid Glass chrome over a quiet backdrop (not over the wallpaper)

The Mac-launcher inspiration (Spotlight, Raycast) is a translucent overlay floating over the desktop wallpaper. **iOS cannot reproduce this**: a full-screen app has no API to see or render the home-screen wallpaper behind it. Liquid Glass refracts whatever sits *behind the glass surface*, which in a full app is the app's own content.

So Quickie gives the glass something to refract:

- **Glass on the chrome** — the input bar and result rows are native iOS 26 `glassEffect` capsules. We never hand-roll blur/translucency, so the material matches the system and responds correctly.
- **A quiet adaptive backdrop** behind them — a calm base (adaptive dark/light, a subtle gradient/tint) that gives the glass depth to refract without competing with text. Not transparent-to-wallpaper, because that is impossible.
- **Tight animation budget** — subtle springs on row slots appearing/disappearing, breadcrumb step transitions, and input focus; nothing that delays a keystroke or the field appearing. Result rows are keyed by **rank**, so re-ranking on a keystroke swaps each slot's content in place — rows never fly around the screen while typing. **Reduce Motion** degrades to fades.

An expressive dynamic backdrop (animated mesh gradient, blurred icons) was considered and rejected for v1 in favor of calm and speed.
