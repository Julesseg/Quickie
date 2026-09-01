# How this report was made

Throwaway tooling for the issue #269 prototype. Run from the repo root with the
simulator lock held (`simlock acquire`), against a booted iPad Pro 13" (M5).

| script | what it does |
| --- | --- |
| `hwkb.sh YES\|NO` | Connects or disconnects the simulator's hardware keyboard. Quits Simulator *before* writing the preference — it flushes its cached prefs over yours on quit, which is why writing first silently does nothing. |
| `pairs.sh` | The docked/palette pairs, light and dark, via `simctl launch` + `simctl io screenshot`. Deliberately not XCUITest: a UI test raises the software keyboard to type, which is the condition palette mode is defined by the absence of. |
| `flip.sh` | Runs the XCUITest burst that films the mode flip. |
| `analyse.py img/` | Endpoint diffs per state, plus a frame-by-frame diff of the flip burst and a contact sheet. |
| `intermediates.py img/flip/` | Classifies every burst frame as docked, palette, or **neither**. The "neither" frames are the bar caught mid-flight — the evidence that says whether the flip is a transition or a cut. |
| `report.py .` | Assembles `index.html`, inlining every image as a data URI so the page stands alone. |

`img/flip/` (the raw 90-frame burst, ~283 MB) is gitignored and reproducible by
re-running `flip.sh`.
