# Installable PR builds

The release workflow builds a **signed, installable `.ipa`** for every PR and
publishes it to a GitHub Pages site, so you can install any PR's build on your
iPhone or iPad straight from Safari — the same flow as
[OnTheRoad](https://github.com/Julesseg/OnTheRoad), but on GitHub's hosted
`macos-15` runner instead of a self-hosted Mac.

The pipeline lives at [`.github/workflows/release.yml`](../.github/workflows/release.yml).

```
PR opened/updated
   └─ build  (macos-15)   archive + export an ad-hoc–signed quickie.ipa
        └─ deploy (ubuntu) upsert this PR's slot, prune to 5, push build-history, deploy Pages
             └─ notify     optional ntfy ping with the install link
```

Visit `https://julesseg.github.io/Quickie/` → tap **Install** on a build (Safari,
on a device whose UDID is in the provisioning profile).

## Why hosted instead of self-hosted works

The only thing the self-hosted Mac gave us for free was a persistent keychain and
provisioning profile. The hosted runner starts clean every run, so the workflow
imports the certificate into a throwaway keychain and drops the profile in place
at runtime — both from repo secrets. Nothing else about the build needs a Mac you
own. (CI still also runs the unsigned simulator tests in `ci.yml`; this is
additive.)

## One-time setup

### 1. Apple Developer (paid program required for on-device install)

1. Register each test device's **UDID** under *Devices*.
2. Make sure the **App ID** `com.julesseguin.quickie` exists with the **App Groups**
   capability enabled (the app uses `group.com.julesseguin.quickie`).
3. Make sure the **App ID** `com.julesseguin.quickie.share` exists, also
   with the **App Groups** capability — the Share Extension is its own bundle and
   writes to the same `group.com.julesseguin.quickie` store.
4. Make sure the **App ID** `com.julesseguin.quickie.widgets` exists, also
   with the **App Groups** capability — the widget extension is its own bundle
   and reads the same `group.com.julesseguin.quickie` store.
5. Create an **Ad Hoc** distribution provisioning profile for `com.julesseguin.quickie`
   that includes those devices, **named exactly `Quickie Ad Hoc`**, and download it
   (`.mobileprovision`).
6. Create a second **Ad Hoc** profile for `com.julesseguin.quickie.share`
   with the same devices, **named exactly `Quickie Share Extension Ad Hoc`**, and
   download it too.
7. Create a third **Ad Hoc** profile for `com.julesseguin.quickie.widgets`
   with the same devices, **named exactly `Quickie Widgets Ad Hoc`**, and download
   it too. (The Release build settings pin all three names; the workflow verifies
   them and fails with a clear message on a mismatch.)
8. Have the matching **Apple Distribution** certificate in your keychain and
   export it as a `.p12` (with a password).

> Ad Hoc only installs on the UDIDs baked into the profile. Add a device → it's
> excluded until you regenerate the profile and update the secret. (TestFlight is
> the alternative if you'd rather not manage UDIDs — different workflow.)

### 2. Repository secrets

*Settings → Secrets and variables → Actions → New repository secret.* Generate the
base64 values with the commands shown (macOS `base64` has no line wrapping by
default, which is what we want):

| Secret | What | How |
| --- | --- | --- |
| `APPLE_CERTIFICATE_P12` | base64 of the `.p12` | `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | the `.p12` export password | — |
| `APPLE_PROVISIONING_PROFILE` | base64 of the app's `.mobileprovision` | `base64 -i Quickie_AdHoc.mobileprovision \| pbcopy` |
| `APPLE_PROVISIONING_PROFILE_EXTENSION` | base64 of the Share Extension's `.mobileprovision` | `base64 -i Quickie_Share_Extension_AdHoc.mobileprovision \| pbcopy` |
| `APPLE_PROVISIONING_PROFILE_WIDGETS` | base64 of the widget extension's `.mobileprovision` | `base64 -i Quickie_Widgets_AdHoc.mobileprovision \| pbcopy` |
| `APPLE_TEAM_ID` | your 10-char Team ID | Apple Developer → Membership |
| `NTFY_TOPIC` | *(optional)* ntfy.sh topic for push notifications | — |

The signing identity name and each profile's UUID are read out of the cert and
profiles at runtime; only the profile *names* are pinned (in the project's Release
build settings — see step 1 above).

Until all six required secrets are set, the `build` job no-ops and the PR check
stays green — the installable build simply doesn't run.

### 3. Enable GitHub Pages

*Settings → Pages → Build and deployment → Source: **GitHub Actions***. The deploy
job uses `upload-pages-artifact` + `deploy-pages`, which needs that source.

**Then allow PR branches to deploy.** Enabling Pages auto-creates a `github-pages`
environment that, by default, only lets the **default branch** deploy — so the
deploy job on a PR branch is rejected at the gate (a ~1-second failure with no
runner and no steps). Fix it at *Settings → Environments → `github-pages` →
Deployment branches and tags*: pick **No restriction**, or keep *Selected
branches and tags* and add a `claude/*` rule to cover the PR branches.

The `build-history` branch is created automatically on the first successful
publish — it's a derived store (force-pushed each run so old `.ipa` blobs don't
pile up in history), not something you commit to by hand.

## App Store / TestFlight releases

[`.github/workflows/release-appstore.yml`](../.github/workflows/release-appstore.yml)
is a **separate** pipeline from the PR builds above. Those are ad-hoc builds for
on-device testing; this one signs for the **App Store** and uploads to App Store
Connect, so the build lands in **TestFlight** and can be promoted to a release.

```
push tag vX.X.X  (or manual dispatch)
   └─ release (macos-15)  stamp version -> archive (automatic signing via ASC API key)
                          -> export app-store .ipa -> altool upload -> optional ntfy
```

Signing uses an **App Store Connect API key** with **automatic signing**:
`xcodebuild` resolves the App Store provisioning profiles for all three bundles
(app + Share Extension + Widgets) at build time, so — unlike the ad-hoc pipeline
— there are **no `.mobileprovision` secrets** to manage. It reuses the same
Apple Distribution certificate, so `APPLE_CERTIFICATE_P12`,
`APPLE_CERTIFICATE_PASSWORD`, and `APPLE_TEAM_ID` are already set.

### One-time setup

1. **App record** — the App IDs `com.julesseguin.quickie`, `.share`, and
   `.widgets` from the ad-hoc setup above already exist; make sure an **app
   record** exists in [App Store Connect](https://appstoreconnect.apple.com)
   (*Apps → +*) for `com.julesseguin.quickie`.
2. **API key** — *Users and Access → Integrations → App Store Connect API → +*,
   role **App Manager**. Download the `.p8` **once** and note its **Key ID** and
   the **Issuer ID**.
3. **Three more secrets** (the cert/team secrets are shared with `release.yml`):

   | Secret | What | How |
   | --- | --- | --- |
   | `APP_STORE_CONNECT_KEY_ID` | the key's Key ID | from step 2 |
   | `APP_STORE_CONNECT_ISSUER_ID` | the key's Issuer ID | from step 2 |
   | `APP_STORE_CONNECT_KEY_P8` | the `.p8` file contents | `pbcopy < AuthKey_XXXX.p8` |

   Until all six required secrets are present, a tagged run **fails fast** with a
   clear message (a deliberate release shouldn't silently no-op like the PR
   pipeline does).

### Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

`MARKETING_VERSION` comes from the tag (`v1.0.0` → `1.0.0`) and
`CURRENT_PROJECT_VERSION` from the CI run number, so every upload is unique and
increasing (App Store Connect rejects duplicate build numbers). Or trigger it
from *Actions → Release (App Store) → Run workflow* with an explicit version.
TestFlight processing takes a few minutes after the run goes green; set
`NTFY_TOPIC` to get pinged when it finishes.

## Files

- `assemble-build-history.mjs` — upserts the current PR's slot into `builds.json`,
  keeps the 5 newest, copies in the `.ipa`, and regenerates the OTA manifests and
  install pages. Pure Node, no dependencies.
- The build + publish pipeline itself lives at `.github/workflows/release.yml`.

## Notes & limits

- **Retention:** 5 most-recent PRs (`RETENTION` in `release.yml`). Older slots and
  their `.ipa`s are pruned.
- **iOS version:** the app targets iOS 26; the build uses the runner's
  latest-stable Xcode, matching `ci.yml`.
- **Versioning:** the OTA manifest uses the short commit SHA as the bundle
  version, so reinstalling the same PR after a new push registers as an update.
