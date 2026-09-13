# Capture recipes

The project's own route comes first (a screenshot test target, a UI-test
helper that attaches screenshots, a storybook, a `scripts/` entry). These
are the fallbacks, one per platform.

## iOS and iPadOS (simulator)

Note which simulators are booted before you start and leave those alone;
shut down every one you boot when the capture is done.

```sh
xcrun simctl list devices booted
xcrun simctl list devices available --json   # pick the newest iPhone / iPad by name
xcrun simctl bootstatus "$UDID" -b           # boots if needed, blocks until ready
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl ui "$UDID" appearance dark      # or light
```

Build, install, launch, shoot:

```sh
cd App && xcodebuild -project <Name>.xcodeproj -scheme <Name> \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath /tmp/ui-report-dd \
  CODE_SIGNING_ALLOWED=NO build
APP=$(find /tmp/ui-report-dd/Build/Products -maxdepth 2 -name "*.app" | head -1)
BUNDLE=$(defaults read "$APP/Info.plist" CFBundleIdentifier)
xcrun simctl install "$UDID" "$APP"
SIMCTL_CHILD_<KEY>=<value> xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -<LaunchArg> <value>
xcrun simctl io "$UDID" screenshot shots/<screen>-<state>-<device>.png
```

`SIMCTL_CHILD_` prefixes an environment variable into the app; the UI test
target shows which `launchEnvironment` keys and `launchArguments` put the
app in a given state (test folders, seeded entries, text sizes).

A state that needs taps: add a throwaway test to the UI test target that
navigates there and attaches `XCUIScreen.main.screenshot()` as an
`XCTAttachment` with `lifetime = .keepAlways`, run only it, export:

```sh
xcodebuild test ... -only-testing:<UITests>/<ReportShots> -resultBundlePath /tmp/ui-report.xcresult
xcrun xcresulttool export attachments --path /tmp/ui-report.xcresult --output-path shots/
```

Remove the throwaway test before committing unless the repo keeps a
screenshot target. A universal app gets each shot on iPhone and iPad.

## Web

Chrome DevTools or Playwright: `npx playwright screenshot --viewport-size=1280,800 --full-page <url> shots/<name>.png`,
`--color-scheme dark` for dark mode, a phone viewport for responsive states.

## macOS app

Launch the built app, find the window id (`GetWindowID <app> <title>` from
Homebrew, or the `id` of `windows` via `osascript`), then
`screencapture -l <id> shots/<name>.png`.

## Android

`adb exec-out screencap -p > shots/<name>.png` on a running emulator.
