import Foundation

/// The identity of *this* build, as read back from the app bundle: the marketing
/// version, the build number, and the git commit the binary was built from
/// (stamped into the built Info.plist by `Scripts/stamp-git-commit.sh`, with a
/// trailing `+` when the working tree was dirty).
///
/// It exists so a build installed on a device can be tied back to a commit
/// without guessing from the version number — see the Settings footer, which is
/// the only place it surfaces.
enum BuildInfo {
    /// e.g. `1.0 (1)`, or just `1.0` when no build number is present.
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }

    /// The short commit hash — `unknown` when the stamping script found no git
    /// checkout to read, and `nil` only if the key is absent entirely, which
    /// means the phase did not run at all (CI's `build-stamp` job exists to
    /// stop that reaching a release). Never a stale hash: the script rewrites
    /// the key on every build rather than skipping on failure.
    static var commit: String? {
        guard let commit = Bundle.main.infoDictionary?["GitCommit"] as? String,
              !commit.isEmpty else { return nil }
        return commit
    }

    /// The one-line identifier shown in Settings, e.g. `Quickie 1.0 (1) · a1b2c3d`.
    static var displayLabel: String {
        guard let commit else { return "Quickie \(versionLabel)" }
        return "Quickie \(versionLabel) · \(commit)"
    }
}
