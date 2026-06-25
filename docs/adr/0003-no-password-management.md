# No password management

Quickie will not read or copy credentials from the system or third-party password managers. iOS exposes no API to read iCloud Keychain or another app's vault — the credential-provider extension only lets an app *supply* credentials into AutoFill, never read others'. The only way to "copy a password" would be for Quickie to own its own encrypted vault and become an AutoFill provider, which is a large security surface (encryption, sync, biometric gating, App Review scrutiny) and off-mission for a quick-input launcher.

We cut the feature entirely rather than defer it. The OS-native AutoFill path, or a user's existing manager via a Shortcut/URL, already covers the need more securely than we could. Revisit only if Quickie ever grows a general encrypted-secrets store for other reasons.
