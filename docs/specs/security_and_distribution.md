# Security and Distribution

This document is the canonical owner for technical security, signing, installer, integrity, and distribution behavior. The [README](../../README.md#security-and-privacy) retains the essential user-facing disclosure.

## App Entitlements and Network Behavior

The app is sandboxed and declares a temporary Mach registration exception for its `InputMethodKit` connection. Its entitlements do not request network client or server access. The current Swift source contains no network client implementation.

These facts describe the checked-in app. They do not remove the inherent risk of granting an input method access to typed text or establish trust in a downloaded binary.

## Signing and Published Artifact Evidence

The documented `make build` command overrides Xcode's signing identity with `-`, producing an ad-hoc signature. The tagged-release workflow uses that command.

The published v0.1.2 artifact provides a concrete snapshot of current distribution behavior:

- its executable is a thin arm64 Mach-O binary;
- its generated property list declares macOS 15.5 as the minimum system version;
- `codesign` reports an ad-hoc signature with no team identifier; and
- the SHA256 digest of its executable matches the release's `checksum.txt` asset.

These are claims about v0.1.2, not promises that later release artifacts have the same architecture or compatibility.

Downloaded applications may receive the `com.apple.quarantine` attribute. An ad-hoc signature does not provide Apple notarization or verified developer identity and does not prevent macOS security warnings.

## Installer Behavior

The release archive includes [`install.sh`](../../install.sh). Before changing the system, the script:

1. checks that `unicorn.app` is beside the script;
2. presents keylogging, notarization, tampering, and data-exfiltration risk disclosures;
3. displays the SHA256 digest of the app's main executable when present; and
4. requests explicit `y` or `yes` confirmation, defaulting to cancellation.

After confirmation, the script recursively removes `com.apple.quarantine` from the bundled app, replaces `~/Library/Input Methods/unicorn.app`, registers it with Launch Services, and terminates matching Unicorn processes. Displaying a digest is not independent integrity verification; users must compare it with a checksum obtained from a trusted source.

## Automation

### Pull-request CI

For pull requests targeting `main`, [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) runs independent lint, native test and coverage, and universal Release verification jobs on hosted macOS. Sanitizer jobs run after the normal native tests pass.

Pull-request CI does not run the installer, copy Unicorn into Input Methods, explicitly register it, activate it, or launch it. Xcode's incidental build-product registration is confined to the disposable runner and discarded when the runner is torn down.

### Tagged releases

Tags matching `v*` or `test-*` trigger [`.github/workflows/release.yml`](../../.github/workflows/release.yml). The workflow:

1. builds with `make build`;
2. packages the app, installer, and executable checksum in `unicorn-macos.zip`;
3. uploads the archive and `checksum.txt` to a draft GitHub release;
4. downloads the archive in a separate job, adds a quarantine attribute, runs the bundled installer with confirmation, and verifies that quarantine is absent from the installed app;
5. publishes a successful `v*` draft; or
6. deletes a `test-*` release and remote test tag after verification runs.

This verifies packaging, installation, and quarantine removal on the GitHub-hosted macOS runner. It does not compare the downloaded executable against `checksum.txt` in the verification job.
