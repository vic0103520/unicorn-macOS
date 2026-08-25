# Security and Distribution

This document is the canonical owner for technical security, versioning, release artifacts, installer recovery, integrity verification, and distribution behavior. The [README](../../README.md#security-and-privacy) retains the essential user-facing disclosure.

## App Entitlements and Network Behavior

The app is sandboxed and declares a temporary Mach registration exception for its `InputMethodKit` connection. Its entitlements do not request network client or server access. The current Swift source contains no network client implementation.

These facts describe the checked-in app. They do not remove the inherent risk of granting an input method access to typed text or establish trust in a downloaded binary.

## Signing and Published Artifact Evidence

The documented `make build` command overrides Xcode's signing identity with `-`, producing an ad-hoc signature. The tagged-release workflow uses the same policy. An ad-hoc signature checks internal consistency, but it carries no Apple Team ID and does not authenticate Unicorn's publisher. Someone who changes an app can ad-hoc sign the changed app again.

The published v0.1.2 artifact is a historical snapshot that predates the current release contract:

- its bundle marketing version is `1.0`, which does not match tag `v0.1.2`;
- its executable is a thin arm64 Mach-O binary;
- its generated property list declares macOS 15.5 as the minimum system version;
- `codesign` reports an ad-hoc signature with no team identifier; and
- its `checksum.txt` matches the executable but does not cover the ZIP, installer, resources, or bundle metadata.

These claims are about v0.1.2, not promises that later release artifacts have the same architecture or compatibility. Releases produced by the current workflow use the contract and artifact set below.

Downloaded applications may receive the `com.apple.quarantine` attribute. An ad-hoc signature does not provide Apple notarization or verified developer identity and does not prevent macOS security warnings.

## Release Version Contract

A production release tag has the exact form `vMAJOR.MINOR.PATCH`, with three nonnegative decimal components and no leading zeroes except the value zero itself. The part after `v` is the app's `CFBundleShortVersionString`. The workflow rejects malformed tags rather than normalizing them.

`CFBundleVersion` is the positive decimal GitHub Actions `github.run_number`. A rerun of the same workflow run therefore uses the same build number. Unpublished test drafts use `test-vMAJOR.MINOR.PATCH-NUMBER`, where the embedded version still controls the bundle marketing version. Test tags are never published.

The tag parser runs before the build. Xcode receives both values explicitly, and packaging then reads the generated `Info.plist` and rejects a mismatch. The packaged `release-metadata.json`, release title, release-note body, downloaded draft, and extracted bundle are checked against the same tag and build number. Contradictory values fail the release.

A production tag is single-use. `make release TAG=vX.Y.Z` refuses an existing local or remote tag, and no production cleanup or re-release target exists. A workflow rerun may replace its own unpublished draft, but it refuses an existing published release. If a published release is defective, operators must use a new version rather than deleting and recreating the old tag.

### Operator commands and recovery

After the intended release commit is reviewed, the production entry point is:

```sh
make release TAG=vX.Y.Z
```

This creates and pushes one new tag. It does not delete test releases or any prior production state. A transiently failed run may be rerun from GitHub Actions; the same run retains its build number and may replace only its unpublished draft. A source or packaging defect requires a corrected commit and a new version tag. Do not move, delete for reuse, or recreate a production tag.

An explicitly approved unpublished integration test uses a unique test tag and is cleaned up by the workflow:

```sh
make test-release VERSION=X.Y.Z
```

`make clean-test-releases` removes only locally known `test-v*` drafts and tags. It refuses production tags. These commands mutate remote GitHub state and are not part of ordinary validation.

## Release Artifact Contract

Packaging copies the validated app and installer into a private staging directory. It records the executable digest in `UNICORN_EXECUTABLE_SHA256` and `release-metadata.json`, normalizes archive entry metadata, and creates `unicorn-macos.zip`. Only after the final ZIP exists does it create the external `SHA256SUMS` file. Release-note Markdown is rendered from those real digest values, not from shell syntax embedded in workflow configuration.

A complete draft has exactly these downloaded assets:

- `unicorn-macos.zip`, containing `unicorn.app`, `install.sh`, `release-metadata.json`, and an internal copy of `UNICORN_EXECUTABLE_SHA256`;
- `SHA256SUMS`, containing one filename-bearing digest for the exact final ZIP bytes; and
- `UNICORN_EXECUTABLE_SHA256`, containing one filename-bearing digest for `unicorn.app/Contents/MacOS/unicorn` inside the ZIP.

The executable digest remains useful for diagnosing or comparing the nested binary, but it is not a substitute for verifying the final ZIP. `SHA256SUMS` detects accidental corruption or a mismatch between the downloaded ZIP and sidecar. It does not prove who produced either file, because an attacker able to replace both same-release assets can replace the digest too.

## Consumer Verification

Download and verify the archive before extracting or executing its installer:

```sh
TAG=vX.Y.Z
REPO=vic0103520/unicorn-macOS
WORKDIR="unicorn-$TAG"
mkdir "$WORKDIR" && cd "$WORKDIR"

gh release download "$TAG" --repo "$REPO" \
  --pattern unicorn-macos.zip \
  --pattern SHA256SUMS \
  --pattern UNICORN_EXECUTABLE_SHA256
shasum -a 256 -c SHA256SUMS
unzip -t unicorn-macos.zip
mkdir extracted
unzip unicorn-macos.zip -d extracted
cmp UNICORN_EXECUTABLE_SHA256 extracted/UNICORN_EXECUTABLE_SHA256
(cd extracted && shasum -a 256 -c UNICORN_EXECUTABLE_SHA256)
```

Then inspect the packaged contract and app identity:

```sh
VERSION=${TAG#v}
METADATA=extracted/release-metadata.json
PLIST=extracted/unicorn.app/Contents/Info.plist
BUILD=$(plutil -extract buildNumber raw -o - "$METADATA")

test "$(plutil -extract tag raw -o - "$METADATA")" = "$TAG"
test "$(plutil -extract marketingVersion raw -o - "$METADATA")" = "$VERSION"
test "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" = "$VERSION"
test "$(plutil -extract CFBundleVersion raw -o - "$PLIST")" = "$BUILD"
test "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" = 'Vic-Shih.inputmethod.unicorn'
test "$(plutil -extract CFBundleExecutable raw -o - "$PLIST")" = unicorn
test -f extracted/unicorn.app/Contents/Resources/keymap.json
test -x extracted/unicorn.app/Contents/MacOS/unicorn
codesign --verify --deep --strict --verbose=2 extracted/unicorn.app
codesign --display --verbose=4 extracted/unicorn.app 2>&1 | grep -F 'Signature=adhoc'
codesign --display --verbose=4 extracted/unicorn.app 2>&1 | grep -F 'TeamIdentifier=not set'
```

These commands verify version and build consistency, required files, the executable identity declared by the bundle, the documented ad-hoc signature policy, and the same final ZIP bytes described by the sidecar. They do not authenticate the publisher, establish Apple Developer ID, or prove that the software is safe. Unicorn currently has no Developer ID signature, notarization, GitHub artifact attestation, or immutable-release verification contract.

After those checks, install only the extracted copy that was just verified:

```sh
sh extracted/install.sh
```

## Installer Behavior and Recovery

The release archive includes [`install.sh`](../../install.sh). Before changing the destination, the script requires the app, release metadata, executable checksum, `Info.plist`, executable, and `keymap.json`. It checks tag, marketing version, build number, bundle identifier, executable name and digest, ad-hoc signature policy, and signature integrity. It then presents the keylogging, notarization, tampering, and data-exfiltration disclosures and requests explicit `y` or `yes` confirmation. Automation may set `UNICORN_ASSUME_YES=1` only after performing equivalent approval in an isolated environment.

After confirmation, the installer removes quarantine from the already validated candidate. It acquires an installation lock, stages a copy in the destination directory, validates the staged copy, and preserves a valid existing `unicorn.app` as a backup before the final same-filesystem move. It snapshots the complete set of processes executing the preserved executable, validates the installed copy, checks that quarantine is absent, and requires both a successful Launch Services registration command and a matching path in the registration database. It then sends `SIGTERM` to those exact old identities and waits up to five seconds for their preserved executable mappings to disappear. The fixed grace period allows orderly shutdown without force-killing a resistant process; the shorter attempt-count override is reserved for deterministic repository tests.

A failed staging step leaves the existing app untouched. A failed replacement, installed-state check, registration, registration postcondition, or process termination restores and re-registers the preserved app. A failed first install removes the incomplete app. None of these paths prints success. The success message is emitted only after all postconditions pass and staging and backup paths are absent.

The installer uses fixed hidden paths inside the destination for its lock, staging app, and backup app. A later run removes staging data protected by a stale dead-process lock. If an interruption left a backup, the next confirmed run validates and restores that backup before attempting the new candidate. It refuses an active or unsafe lock, a symbolic-link destination app, or an invalid existing installation rather than deleting uncertain data. Paths are quoted, including paths containing spaces.

`make install` packages the source build into the same metadata format and invokes this installer. Destructive-path tests override the destination and Launch Services command, so repository validation does not replace a developer's installed Unicorn.

## Release Automation

### Pull-request CI

For pull requests targeting `main`, [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) installs SwiftLint, runs `make lint`, runs `make test`, and runs `make install`. `make test` includes hostless core tests, release-contract tests, transactional installer tests, and universal Debug compilation. The install target builds, packages, and transactionally installs the app into the runner user's input-method directory.

### Tagged releases

Tags matching `v*` or `test-v*` trigger [`.github/workflows/release.yml`](../../.github/workflows/release.yml). One job with job-level `contents: write` permission performs this sequence:

1. parse the tag and select `github.run_number` as the build number;
2. run release and installer regression tests;
3. build the app with explicit version values, validate it, create the deterministic final ZIP, hash it, and render release notes;
4. create a complete draft with the exact three assets;
5. download those assets into a clean directory and compare them byte-for-byte with the build outputs;
6. validate checksum syntax and bytes, ZIP structure, packaged metadata, required files, executable digest and identity, ad-hoc signature policy, release title, release body, and draft state;
7. install the extracted downloaded app under a temporary home and destination, then check its bundle versions and quarantine state; and
8. publish a successful production draft or delete an unpublished test draft and test tag.

Publication occurs only after draft verification and isolated installation. A production failure leaves its draft for diagnosis. Re-running that unpublished draft uses the same tag version and workflow run number and replaces the draft with newly verified assets. Once published, the workflow refuses the same tag, and the operator must create a new version for any correction.

The workflow does not publish or claim GitHub attestations, immutable releases, Developer ID identity, or notarization. Those controls require separate policy and security work.
