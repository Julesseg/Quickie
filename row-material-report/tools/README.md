# How this report was made

Throwaway tooling for the issue #286 prototype. Run from the repo root against
two booted simulators that have the prototype build installed. Fresh
`simctl create`d devices, not the shared ones: a signed-in Apple Account posts
a validation alert over the launcher, and the first keyboard use shows a
bilingual-keyboard tutorial — both were dismissed by device prefs, not by tapping.

| script | what it does |
| --- | --- |
| `capture.sh <udid> <iphone\|ipad>` | The row × hero matrix, light and dark, via `simctl launch` + `simctl io screenshot`. Not XCUITest, so the hero is photographed the way it ships (no `-uitest-instant-motion`), 7 s after launch, at rest. |
| `film.sh <udid> <iphone\|ipad> <row>` | Films one clip per hero treatment while `-proto-autotype` types "settings" a character at a time, then trims it and pulls a 4 fps frame strip. |
| `sheet.py <device> <appearance>` | One contact sheet per device/appearance, for judging. |
| `report.py` | Assembles `index.html`, inlining every image as a data URI so the page stands alone. |

The long-press frames came from `App/QuickieUITests/PrototypeLongPressTests.swift`
(XCUITest is the only thing that can hold a press), exported with
`xcrun xcresulttool export attachments`.

The raw PNGs are not committed; the `img/` tree is the same frames at half size as JPEG.
