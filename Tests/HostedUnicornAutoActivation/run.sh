#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedUnicornAutoActivation"
EVIDENCE="$BUILD_ROOT/evidence"
BIN="$BUILD_ROOT/bin"
PRODUCTS="$BUILD_ROOT/Products"
CLIENT_APP="$BUILD_ROOT/HostedUnicornActivationClient.app"
HELPER="$BIN/UnicornSourceHelper"
BUILT_APP="$PRODUCTS/Release/unicorn.app"
STAGING="$BUILD_ROOT/supported-installer"
INSTALLED_APP="$HOME/Library/Input Methods/unicorn.app"
PRODUCER_EXIT="$EVIDENCE/producer-exit-code.txt"
EXPERIMENT="${UNICORN_EXPERIMENT:-unicorn-supported-installer}"
case "$EXPERIMENT" in
    unicorn-supported-installer|unicorn-post-approval-mode-enable|unicorn-semantic-input-source-add) ;;
    *) printf 'Unsupported UNICORN_EXPERIMENT: %s\n' "$EXPERIMENT" >&2; exit 64 ;;
esac

rm -rf "$BUILD_ROOT"
mkdir -p "$EVIDENCE" "$BIN" "$CLIENT_APP/Contents/MacOS"
python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
    init "$EVIDENCE" "$INSTALLED_APP" "$EXPERIMENT"

record_phase() {
    local phase="$1"
    local state="$2"
    python3 - "$EVIDENCE/phases.jsonl" "$phase" "$state" <<'PY'
import datetime as dt
import json
import pathlib
import sys
with pathlib.Path(sys.argv[1]).open("a") as handle:
    handle.write(json.dumps({
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "phase": sys.argv[2],
        "state": sys.argv[3],
    }, sort_keys=True) + "\n")
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
    "xcodebuild.log": 2_097_152,
    "system-log.jsonl": 4_194_304,
    "processes-final.txt": 262_144,
}
for name, maximum in limits.items():
    path = root / name
    if path.exists() and path.stat().st_size > maximum:
        content = path.read_bytes()
        path.write_bytes(b"[truncated to bounded tail]\n" + content[-maximum:])
PY
}

collect_evidence() {
    set +e
    record_phase "evidence-collection" "started"
    if [[ -x "$HELPER" ]]; then
        "$HELPER" sources "final-evidence-collection-before-cleanup" \
            "$EVIDENCE/input-sources-final-evidence.json" \
            >"$EVIDENCE/input-sources-final-command.log" 2>&1
    fi
    ps -axo pid=,ppid=,uid=,user=,state=,etime=,lstart=,comm=,args= \
        >"$EVIDENCE/processes-final.txt" 2>&1
    /usr/bin/log show \
        --last 20m \
        --style ndjson \
        --info \
        --debug \
        --predicate \
        'subsystem CONTAINS[c] "TextInput" OR subsystem CONTAINS[c] "LaunchServices" OR subsystem CONTAINS[c] "RunningBoard" OR subsystem CONTAINS[c] "InputMethodKit" OR category CONTAINS[c] "TextInput" OR process == "unicorn" OR process == "imklaunchagent" OR process == "lsd" OR process == "launchservicesd" OR process == "runningboardd" OR process == "amfid" OR process == "taskgated" OR process == "syspolicyd" OR process == "ReportCrash" OR process == "CrashReporterSupportHelper" OR eventMessage CONTAINS[c] "Vic-Shih.inputmethod.unicorn" OR eventMessage CONTAINS[c] "LaunchInputMethod" OR eventMessage CONTAINS[c] "IMKXPCEndpoint" OR eventMessage CONTAINS[c] "dyld"' \
        2>"$EVIDENCE/system-log.stderr" \
        | tail -n 2500 >"$EVIDENCE/system-log.jsonl"
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
    "$ROOT/Tests/HostedUnicornAutoActivation/cleanup.sh" \
        >"$EVIDENCE/cleanup-command.log" 2>&1
    python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
        finalize "$EVIDENCE" "$status"
    exit "$status"
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap finish EXIT

record_phase "compile-native-support" "started"
xcrun swiftc \
    -swift-version 5 \
    "$ROOT/Tests/HostedUnicornAutoActivation/UnicornSourceHelper.swift" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon \
    -framework CoreGraphics \
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
    <string>Hosted Unicorn Automatic Activation Client</string>
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

record_phase "fresh-runner-aqua-preflight" "started"
python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
    preflight "$EVIDENCE" "$HELPER"
record_phase "fresh-runner-aqua-preflight" "completed"

record_phase "build-exact-unicorn-revision" "started"
if ! make -C "$ROOT" build \
    CONFIG=Release \
    ARCHS=arm64 \
    BUILD_DIR="$PRODUCTS" \
    NO_COLOR=1 \
    >"$EVIDENCE/xcodebuild.log" 2>&1; then
    record_phase "build-exact-unicorn-revision" "failed"
    exit 1
fi
test -d "$BUILT_APP"
test -x "$BUILT_APP/Contents/MacOS/unicorn"
cmp "$ROOT/unicorn/keymap.json" "$BUILT_APP/Contents/Resources/keymap.json"
python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
    record-build "$EVIDENCE" "$BUILT_APP" "$CLIENT_APP"
record_phase "build-exact-unicorn-revision" "completed"

record_phase "install-appium" "started"
npm install --global appium@3.7.0 --no-audit --no-fund \
    >"$EVIDENCE/npm-install.log" 2>&1
appium driver install mac2@4.2.0 \
    >"$EVIDENCE/appium-driver-install.log" 2>&1
appium driver doctor mac2 >"$EVIDENCE/appium-doctor.log" 2>&1 || true
appium --version >"$EVIDENCE/appium-version.txt"
appium driver list --installed >"$EVIDENCE/appium-drivers.txt"
record_phase "install-appium" "completed"

record_phase "run-supported-unicorn-installer" "started"
mkdir -p "$STAGING"
ditto "$BUILT_APP" "$STAGING/unicorn.app"
cp "$ROOT/install.sh" "$STAGING/install.sh"
python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
    record-installation "$EVIDENCE" "$INSTALLED_APP" "$HELPER" before
printf 'y\n' | sh "$STAGING/install.sh" \
    >"$EVIDENCE/supported-installer.stdout.log" \
    2>"$EVIDENCE/supported-installer.stderr.log"
test -d "$INSTALLED_APP"
python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
    record-installation "$EVIDENCE" "$INSTALLED_APP" "$HELPER" after
record_phase "run-supported-unicorn-installer" "completed"

record_phase "select-activate-and-compose-without-prelaunch" "started"
python3 "$ROOT/Tests/HostedUnicornAutoActivation/control.py" \
    run "$EVIDENCE" "$HELPER" "$CLIENT_APP" "$INSTALLED_APP" "$EXPERIMENT"
record_phase "select-activate-and-compose-without-prelaunch" "completed"
