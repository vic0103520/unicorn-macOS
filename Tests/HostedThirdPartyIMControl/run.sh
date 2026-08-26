#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedThirdPartyIMControl"
EVIDENCE="$BUILD_ROOT/evidence"
BIN="$BUILD_ROOT/bin"
HELPER="$BIN/ThirdPartySourceHelper"
CLIENT_APP="$BUILD_ROOT/HostedThirdPartyControlClient.app"
PACKAGE="$BUILD_ROOT/Squirrel-1.1.2.pkg"
EXPANDED="$BUILD_ROOT/expanded"
EXPERIMENT="${SQUIRREL_EXPERIMENT:-third-party-squirrel-control}"
case "$EXPERIMENT" in
    third-party-squirrel-control|squirrel-automatic-baseline|squirrel-automatic-ls-refresh|squirrel-official-installer) ;;
    *) printf 'Unsupported SQUIRREL_EXPERIMENT: %s\n' "$EXPERIMENT" >&2; exit 64 ;;
esac
if [[ "$EXPERIMENT" == "squirrel-official-installer" ]]; then
    INSTALLED_APP="/Library/Input Methods/Squirrel.app"
else
    INSTALLED_APP="$HOME/Library/Input Methods/Squirrel.app"
fi
SQUIRREL="$INSTALLED_APP/Contents/MacOS/Squirrel"
ASSET_URL="https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg"
ASSET_SHA256="614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287"
PRODUCER_EXIT="$EVIDENCE/producer-exit-code.txt"

rm -rf "$BUILD_ROOT"
mkdir -p "$EVIDENCE" "$BIN" "$CLIENT_APP/Contents/MacOS"
python3 "$ROOT/Tests/HostedThirdPartyIMControl/control.py" \
    init "$EVIDENCE" "$INSTALLED_APP" "$EXPERIMENT"

record_phase() {
    local phase="$1"
    local state="$2"
    python3 - "$EVIDENCE/phases.jsonl" "$phase" "$state" <<'PY'
import datetime as dt
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "phase": sys.argv[2],
    "state": sys.argv[3],
}
with path.open("a") as handle:
    handle.write(json.dumps(value, sort_keys=True) + "\n")
PY
}

truncate_evidence() {
    python3 - "$EVIDENCE" <<'PY'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
limits = {
    "appium.log": 2_097_152,
    "npm-install.log": 1_048_576,
    "appium-driver-install.log": 1_048_576,
    "system-log.jsonl": 4_194_304,
    "direct-launch-unified-log.jsonl": 4_194_304,
    "direct-launch-unified-log.stderr": 262_144,
    "direct-launch-stdout.log": 1_048_576,
    "direct-launch-stderr.log": 1_048_576,
    "direct-launch-process-timeline.jsonl": 1_048_576,
    "processes-final.txt": 262_144,
    "squirrel-build.log": 1_048_576,
}
for name, maximum in limits.items():
    path = root / name
    if path.exists() and path.stat().st_size > maximum:
        content = path.read_bytes()
        if name.startswith("direct-launch-"):
            half = maximum // 2
            path.write_bytes(
                content[:half]
                + b"\n[bounded middle omitted]\n"
                + content[-half:]
            )
        else:
            path.write_bytes(b"[truncated to bounded tail]\n" + content[-maximum:])
PY
}

collect_evidence() {
    set +e
    record_phase "evidence-collection" "started"
    if [[ -x "$HELPER" ]]; then
        "$HELPER" sources "final-evidence-collection-before-cleanup" \
            "$EVIDENCE/input-sources-final-before-cleanup.json" \
            >"$EVIDENCE/input-sources-final-command.log" 2>&1
    fi
    ps -axo pid=,ppid=,user=,comm=,args= >"$EVIDENCE/processes-final.txt" 2>&1
    /usr/bin/log show \
        --last 15m \
        --style ndjson \
        --info \
        --debug \
        --predicate \
        'subsystem CONTAINS[c] "TextInput" OR subsystem CONTAINS[c] "LaunchServices" OR subsystem CONTAINS[c] "RunningBoard" OR subsystem CONTAINS[c] "InputMethodKit" OR category CONTAINS[c] "TextInput" OR process == "Squirrel" OR process == "imklaunchagent" OR process == "lsd" OR process == "launchservicesd" OR process == "runningboardd" OR process == "amfid" OR process == "taskgated" OR process == "syspolicyd" OR process == "ReportCrash" OR process == "CrashReporterSupportHelper" OR eventMessage CONTAINS[c] "im.rime.inputmethod.Squirrel" OR eventMessage CONTAINS[c] "LaunchInputMethod" OR eventMessage CONTAINS[c] "IMKXPCEndpoint" OR eventMessage CONTAINS[c] "dyld"' \
        2>"$EVIDENCE/system-log.stderr" \
        | tail -n 2000 >"$EVIDENCE/system-log.jsonl"
    /usr/sbin/screencapture -x "$EVIDENCE/desktop-final.png" \
        >"$EVIDENCE/screencapture.stdout" 2>"$EVIDENCE/screencapture.stderr"
    truncate_evidence
    record_phase "evidence-collection" "completed"
    set -e
}

finish() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    printf '%s\n' "$status" >"$PRODUCER_EXIT"
    collect_evidence
    set +e
    "$ROOT/Tests/HostedThirdPartyIMControl/cleanup.sh" \
        >"$EVIDENCE/cleanup-command.log" 2>&1
    python3 "$ROOT/Tests/HostedThirdPartyIMControl/control.py" \
        finalize "$EVIDENCE" "$status"
    exit "$status"
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap finish EXIT

record_phase "compile-native-support" "started"
xcrun swiftc \
    -swift-version 5 \
    "$ROOT/Tests/HostedThirdPartyIMControl/ThirdPartySourceHelper.swift" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon \
    -framework CoreGraphics \
    -framework CoreServices \
    -framework Foundation \
    -framework SystemConfiguration \
    -o "$HELPER"

xcrun swiftc \
    -parse-as-library \
    -swift-version 5 \
    "$ROOT/Tests/HostedIMKProbe/TestClient.swift" \
    -framework AppKit \
    -framework Foundation \
    -o "$CLIENT_APP/Contents/MacOS/HostedIMKProbeClient"
cat >"$CLIENT_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HostedIMKProbeClient</string>
    <key>CFBundleIdentifier</key>
    <string>dev.unicorn.hosted-imk-probe.client</string>
    <key>CFBundleName</key>
    <string>Third-Party Input Method Control Client</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.5</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$CLIENT_APP"
record_phase "compile-native-support" "completed"

record_phase "runner-preflight" "started"
python3 "$ROOT/Tests/HostedThirdPartyIMControl/control.py" \
    preflight "$EVIDENCE" "$HELPER"
python3 - "$EVIDENCE/installation-state.json" "$EVIDENCE/input-sources-initial.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
sources = json.loads(pathlib.Path(sys.argv[2]).read_text())
preexisting_paths = [item["path"] for item in state["trackedPaths"] if item["existedBefore"]]
preexisting_sources = [
    item for item in sources.get("sources", [])
    if item.get("bundleID") == "im.rime.inputmethod.Squirrel"
]
if preexisting_paths or preexisting_sources:
    raise SystemExit(
        "Refusing to modify pre-existing Squirrel state: "
        + repr({"paths": preexisting_paths, "sources": preexisting_sources})
    )
PY
record_phase "runner-preflight" "completed"

record_phase "download-and-verify-official-release" "started"
curl --fail --location --retry 3 --show-error --silent \
    -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/rime/squirrel/releases/tags/1.1.2' \
    --output "$EVIDENCE/official-release-api.json"
curl --fail --location --retry 3 --show-error --silent \
    -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/rime/squirrel/commits/876adebaf2f612951dcdca8a591de65401222b9a' \
    --output "$EVIDENCE/release-commit-api.json"
python3 - \
    "$EVIDENCE/official-release-api.json" \
    "$EVIDENCE/release-commit-api.json" <<'PY'
import json
import pathlib
import sys
release = json.loads(pathlib.Path(sys.argv[1]).read_text())
commit = json.loads(pathlib.Path(sys.argv[2]).read_text())
asset = next(
    item for item in release.get("assets", [])
    if item.get("name") == "Squirrel-1.1.2.pkg"
)
expected = {
    "tag": "1.1.2",
    "digest": "sha256:614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287",
    "url": "https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg",
    "commit": "876adebaf2f612951dcdca8a591de65401222b9a",
}
checks = {
    "tag": release.get("tag_name") == expected["tag"],
    "stable": not release.get("draft") and not release.get("prerelease"),
    "assetDigest": asset.get("digest") == expected["digest"],
    "assetURL": asset.get("browser_download_url") == expected["url"],
    "commit": commit.get("sha") == expected["commit"],
    "commitSignatureVerified": commit.get("commit", {}).get("verification", {}).get("verified") is True,
}
if not all(checks.values()):
    raise SystemExit(f"Pinned release API verification failed: {checks}")
PY
curl --fail --location --retry 3 --show-error --silent \
    "$ASSET_URL" --output "$PACKAGE"
printf '%s  %s\n' "$ASSET_SHA256" "$PACKAGE" \
    | shasum -a 256 --check \
    >"$EVIDENCE/asset-digest-check.log" 2>&1
pkgutil --check-signature "$PACKAGE" \
    >"$EVIDENCE/package-signature.log" 2>&1
xcrun stapler validate "$PACKAGE" \
    >"$EVIDENCE/package-stapler.log" 2>&1
pkgutil --expand-full "$PACKAGE" "$EXPANDED"
test -d "$EXPANDED/Payload/Squirrel.app"
if [[ "$EXPERIMENT" == "squirrel-official-installer" ]]; then
    cp "$EXPANDED/Scripts/postinstall" "$EVIDENCE/package-postinstall-executed-by-installer.txt"
    PROVENANCE_APP="$EXPANDED/Payload/Squirrel.app"
else
    cp "$EXPANDED/Scripts/postinstall" "$EVIDENCE/package-postinstall-not-executed.txt"
    mkdir -p "$(dirname "$INSTALLED_APP")"
    ditto "$EXPANDED/Payload/Squirrel.app" "$INSTALLED_APP"
    PROVENANCE_APP="$INSTALLED_APP"
fi
python3 "$ROOT/Tests/HostedThirdPartyIMControl/control.py" \
    provenance "$EVIDENCE" "$PACKAGE" "$PROVENANCE_APP"
record_phase "download-and-verify-official-release" "completed"

if [[ "$EXPERIMENT" == "squirrel-official-installer" ]]; then
    record_phase "execute-pinned-official-installer" "started"
    python3 - "$EVIDENCE/official-installer-side-effects-before.json" "$HELPER" <<'PY'
import datetime as dt
import json
import pathlib
import subprocess
import sys
helper = sys.argv[2]
def run(command):
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return {"command": command, "exitCode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "systemAppExists": pathlib.Path("/Library/Input Methods/Squirrel.app").exists(),
    "receipt": run(["pkgutil", "--pkg-info", "im.rime.inputmethod.Squirrel"]),
    "process": run(["pgrep", "-x", "Squirrel"]),
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
    sudo -n installer -verboseR -pkg "$PACKAGE" -target / \
        >"$EVIDENCE/official-installer.stdout.log" \
        2>"$EVIDENCE/official-installer.stderr.log"
    test -d "$INSTALLED_APP"
    python3 - "$EVIDENCE/official-installer-side-effects.json" "$EVIDENCE/official-installer-side-effects-before.json" "$HELPER" <<'PY'
import datetime as dt
import json
import pathlib
import subprocess
import sys
output = pathlib.Path(sys.argv[1])
before = json.loads(pathlib.Path(sys.argv[2]).read_text())
helper = sys.argv[3]
def run(command):
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return {"command": command, "exitCode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}
source_path = output.with_name("input-sources-after-official-installer.json")
source = run([helper, "sources", "after-official-installer-before-exact-sequence", str(source_path)])
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "before": before,
    "systemAppExists": pathlib.Path("/Library/Input Methods/Squirrel.app").exists(),
    "receipt": run(["pkgutil", "--pkg-info", "im.rime.inputmethod.Squirrel"]),
    "process": run(["pgrep", "-x", "Squirrel"]),
    "filesystem": run(["stat", "-f", "%N|%Su|%Sg|%Sp", "/Library/Input Methods/Squirrel.app", "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"]),
    "sourceSnapshotCommand": source,
    "sourceSnapshotPath": source_path.name,
    "packageInstallerExecuted": True,
    "packagePostinstallExecuted": True,
}
output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
    python3 - "$EVIDENCE/provenance.json" "$EVIDENCE/summary.json" <<'PY'
import json
import pathlib
import sys
provenance_path = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])
provenance = json.loads(provenance_path.read_text())
provenance["installationMethod"].update({
    "method": "pinned official signed and notarized Installer package executed with root authorization on a fresh disposable runner",
    "packageInstallerExecuted": True,
    "packagePostinstallExecuted": True,
})
provenance_path.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
summary = json.loads(summary_path.read_text())
summary["provenance"]["packageInstallerExecuted"] = True
summary["provenance"]["packagePostinstallExecuted"] = True
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
PY
    record_phase "execute-pinned-official-installer" "completed"
fi

record_phase "prepare-official-input-method-data" "started"
python3 - "$SQUIRREL" "$INSTALLED_APP/Contents/SharedSupport" "$EVIDENCE/squirrel-build.log" <<'PY'
import pathlib
import subprocess
import sys
executable = sys.argv[1]
working_directory = sys.argv[2]
log_path = pathlib.Path(sys.argv[3])
with log_path.open("w") as log:
    completed = subprocess.run(
        [executable, "--build"],
        cwd=working_directory,
        stdout=log,
        stderr=subprocess.STDOUT,
        timeout=180,
        check=False,
        text=True,
    )
if completed.returncode != 0:
    raise SystemExit(f"Squirrel --build returned {completed.returncode}")
PY
"$HELPER" sources "after-build-before-registration" \
    "$EVIDENCE/input-sources-after-build-before-registration.json" \
    >"$EVIDENCE/input-sources-after-build-command.log" 2>&1
python3 - "$EVIDENCE/process-after-build-before-registration.json" <<'PY'
import datetime as dt
import json
import pathlib
import subprocess
import sys
completed = subprocess.run(
    ["pgrep", "-x", "Squirrel"], capture_output=True, text=True, check=False
)
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "pgrepExitCode": completed.returncode,
    "stdout": completed.stdout,
    "stderr": completed.stderr,
    "processAbsent": completed.returncode == 1,
    "purpose": "Prove later live Squirrel evidence is not a leftover from data preparation",
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
if not value["processAbsent"]:
    raise SystemExit("Squirrel remained running after --build; later launch attribution would be ambiguous")
PY
record_phase "prepare-official-input-method-data" "completed"

record_phase "install-appium" "started"
npm install --global appium@3.7.0 --no-audit --no-fund \
    >"$EVIDENCE/npm-install.log" 2>&1
appium driver install mac2@4.2.0 \
    >"$EVIDENCE/appium-driver-install.log" 2>&1
appium driver doctor mac2 >"$EVIDENCE/appium-doctor.log" 2>&1 || true
appium --version >"$EVIDENCE/appium-version.txt"
appium driver list --installed >"$EVIDENCE/appium-drivers.txt"
record_phase "install-appium" "completed"

record_phase "register-approve-direct-launch-select-and-compose" "started"
python3 - "$EVIDENCE/installation-state.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text())
value["selectionStarted"] = True
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
python3 "$ROOT/Tests/HostedThirdPartyIMControl/control.py" \
    run "$EVIDENCE" "$HELPER" "$CLIENT_APP" "$INSTALLED_APP" "$EXPERIMENT"
record_phase "register-approve-direct-launch-select-and-compose" "completed"
