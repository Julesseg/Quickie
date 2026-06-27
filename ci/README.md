# Installable PR builds

The release workflow builds a **signed, installable `.ipa`** for every PR and
publishes it to a GitHub Pages site, so you can install any PR's build on your
iPhone straight from Safari — the same flow as
[OnTheRoad](https://github.com/Julesseg/OnTheRoad), but on GitHub's hosted
`macos-15` runner instead of a self-hosted Mac.

> **Activate it first.** The workflow ships parked at [`ci/release.yml`](release.yml)
> because the automation that opened this PR can't write under
> `.github/workflows/` (that needs the `workflow` OAuth scope / GitHub-App
> permission). Move it into place with your own credentials and push:
>
> ```sh
> git mv ci/release.yml .github/workflows/release.yml
> git commit -m "Activate release workflow"
> git push
> ```
>
> It's a plain copy — review it at `ci/release.yml`, then move it as-is.

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
3. Create an **Ad Hoc** distribution provisioning profile for `com.julesseguin.quickie`
   that includes those devices, and download it (`.mobileprovision`).
4. Have the matching **Apple Distribution** certificate in your keychain and
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
| `APPLE_PROVISIONING_PROFILE` | base64 of the `.mobileprovision` | `base64 -i Quickie_AdHoc.mobileprovision \| pbcopy` |
| `APPLE_TEAM_ID` | your 10-char Team ID | Apple Developer → Membership |
| `NTFY_TOPIC` | *(optional)* ntfy.sh topic for push notifications | — |

The signing identity name and the profile's name/UUID are read out of the cert and
profile at runtime, so there's nothing else to copy.

Until all four required secrets are set, the `build` job no-ops and the PR check
stays green — the installable build simply doesn't run.

### 3. Enable GitHub Pages

*Settings → Pages → Build and deployment → Source: **GitHub Actions***. The deploy
job uses `upload-pages-artifact` + `deploy-pages`, which needs that source.

The `build-history` branch is created automatically on the first successful
publish — it's a derived store (force-pushed each run so old `.ipa` blobs don't
pile up in history), not something you commit to by hand.

## Files

- `assemble-build-history.mjs` — upserts the current PR's slot into `builds.json`,
  keeps the 5 newest, copies in the `.ipa`, and regenerates the OTA manifests and
  install pages. Pure Node, no dependencies.
- `release.yml` — the build + publish pipeline. Parked here; move it to
  `.github/workflows/release.yml` to activate (see the box at the top).

## Notes & limits

- **Retention:** 5 most-recent PRs (`RETENTION` in `release.yml`). Older slots and
  their `.ipa`s are pruned.
- **iOS version:** the app targets iOS 26; the build uses the runner's
  latest-stable Xcode, matching `ci.yml`.
- **Versioning:** the OTA manifest uses the short commit SHA as the bundle
  version, so reinstalling the same PR after a new push registers as an update.
