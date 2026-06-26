# No native app launcher

Quickie will **not** offer launching/detecting installed apps as a first-class feature. iOS provides no way to enumerate installed apps, and the two partial workarounds are both inadequate:

- `canOpenURL` + `LSApplicationQueriesSchemes` requires hard-declaring every app's URL scheme at build time and only covers a curated catalog we'd have to own and maintain (the top-N apps), not the user's actual device.
- The Screen Time / FamilyControls `FamilyActivityPicker` returns **opaque, non-launchable `ApplicationToken`s** (bundle id and display name are nil by design), and requires the gated Family Controls entitlement Apple grants only to parental-control apps.

We judged the curated-catalog payoff too low for the maintenance cost and decided to cut it rather than ship a half-feature. App-launching needs are deferred to user-supplied **iOS Shortcuts** and **Quicklinks** (URL schemes), which can launch any app via `open(url)` without detection.

This is reversible — if a compelling approach emerges we can revisit — but the default is: Quickie does not launch apps directly.
