#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedBuiltinInputSourceControl"
EVIDENCE="$BUILD_ROOT/evidence"
BIN="$BUILD_ROOT/bin"
HELPER="$BIN/BuiltinSourceHelper"
CLIENT_APP="$BUILD_ROOT/BuiltinSourceControlClient.app"
STATE="$EVIDENCE/control-state.json"
PRODUCER_EXIT="$EVIDENCE/producer-exit-code.txt"

rm -rf "$BUILD_ROOT"
mkdir -p "$EVIDENCE" "$BIN" "$CLIENT_APP/Contents/MacOS"

collect_evidence() {
    set +e
    ps -axo pid=,ppid=,user=,comm=,args= >"$EVIDENCE/processes-final.txt" 2>&1
    /usr/bin/log show \
        --last 15m \
        --style json \
        --info \
        --predicate \
        'process == "System Settings" OR process == "HostedIMKProbeClient" OR process == "WebDriverAgentRunner" OR process == "imklaunchagent"' \
        2>"$EVIDENCE/system-log.stderr" \
        | tail -n 2000 >"$EVIDENCE/system-log.jsonl"
    /usr/sbin/screencapture -x "$EVIDENCE/desktop-final.png" \
        >"$EVIDENCE/screencapture.stdout" 2>"$EVIDENCE/screencapture.stderr"
    python3 - "$EVIDENCE" <<'PY'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
for name, maximum in {
    "appium.log": 2_097_152,
    "npm-install.log": 1_048_576,
    "appium-driver-install.log": 1_048_576,
    "system-log.jsonl": 2_097_152,
    "processes-final.txt": 262_144,
}.items():
    path = root / name
    if path.exists() and path.stat().st_size > maximum:
        path.write_bytes(b"[truncated to bounded tail]\n" + path.read_bytes()[-maximum:])
PY
    set -e
}

finish() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    printf '%s\n' "$status" >"$PRODUCER_EXIT"
    collect_evidence
    "$ROOT/Tests/HostedBuiltinInputSourceControl/cleanup.sh" \
        >"$EVIDENCE/final-cleanup-command.log" 2>&1
    exit "$status"
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap finish EXIT

xcrun swiftc \
    -swift-version 5 \
    "$ROOT/Tests/HostedBuiltinInputSourceControl/BuiltinSourceHelper.swift" \
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
    <string>Built-in Input Source Control Client</string>
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

sudo -n automationmodetool enable-automationmode-without-authentication \
    >"$EVIDENCE/automation-mode-enable.log" 2>&1
automationmodetool >"$EVIDENCE/automation-mode-after.log" 2>&1

npm install --global appium@3.7.0 --no-audit --no-fund \
    >"$EVIDENCE/npm-install.log" 2>&1
appium driver install mac2@4.2.0 \
    >"$EVIDENCE/appium-driver-install.log" 2>&1
appium driver doctor mac2 >"$EVIDENCE/appium-doctor.log" 2>&1 || true
appium --version >"$EVIDENCE/appium-version.txt"
appium driver list --installed >"$EVIDENCE/appium-drivers.txt"

"$HELPER" capture-state com.apple.keylayout.Dvorak "$STATE" \
    >"$EVIDENCE/capture-state-command.log" 2>&1

python3 "$ROOT/Tests/HostedBuiltinInputSourceControl/control.py" \
    "$EVIDENCE" "$HELPER" "$CLIENT_APP" "$STATE"
