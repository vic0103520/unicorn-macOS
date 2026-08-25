#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedIMKProbe"
EVIDENCE="$BUILD_ROOT/evidence"
BIN_DIR="$BUILD_ROOT/bin"
PRODUCTS="$BUILD_ROOT/Products"
OBJECTS="$BUILD_ROOT/Intermediates"
CLIENT_APP="$BUILD_ROOT/HostedIMKProbeClient.app"
HELPER="$BIN_DIR/ProbeHelper"
PROBE_BUNDLE_ID="dev.unicorn.inputmethod.hosted-imk-probe"
PROBE_MODE_ID="dev.unicorn.inputmethod.hosted-imk-probe.mode"
PROBE_EXECUTABLE="UnicornHostedIMKProbe"
XCODE_APP="$PRODUCTS/Release/unicorn.app"
BUILT_APP="$BUILD_ROOT/UnicornHostedIMKProbe.app"
INSTALLED_APP="$HOME/Library/Input Methods/UnicornHostedIMKProbe.app"
PRODUCER_EXIT_FILE="$EVIDENCE/producer-exit-code.txt"
SELECTION_PID=""

rm -rf "$BUILD_ROOT"
mkdir -p "$EVIDENCE" "$BIN_DIR"
python3 "$ROOT/Tests/HostedIMKProbe/probe.py" init "$EVIDENCE"

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

truncate_file() {
    local path="$1"
    local maximum="$2"
    python3 - "$path" "$maximum" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
maximum = int(sys.argv[2])
if path.exists() and path.stat().st_size > maximum:
    data = path.read_bytes()[-maximum:]
    path.write_bytes(b"[truncated to bounded tail]\n" + data)
PY
}

collect_evidence() {
    set +e
    record_phase "evidence-collection" "started"

    if [[ -x "$HELPER" ]]; then
        "$HELPER" sources "$EVIDENCE/input-sources-final-before-cleanup.json" \
            >"$EVIDENCE/input-sources-final-command.log" 2>&1
    fi

    ps -axo pid=,ppid=,user=,comm=,args= >"$EVIDENCE/processes-final.txt" 2>&1

    /usr/bin/log show \
        --last 15m \
        --style json \
        --info \
        --predicate \
        'process == "UnicornHostedIMKProbe" OR process == "imklaunchagent" OR subsystem == "Vic-Shih.inputmethod.unicorn" OR eventMessage CONTAINS[c] "hosted-imk-probe"' \
        2>"$EVIDENCE/system-log.stderr" \
        | tail -n 2000 >"$EVIDENCE/system-log.jsonl"

    mkdir -p "$EVIDENCE/crashes"
    while IFS= read -r crash; do
        [[ -f "$crash" ]] || continue
        tail -c 1048576 "$crash" >"$EVIDENCE/crashes/$(basename "$crash")"
    done < <(
        find "$HOME/Library/Logs/DiagnosticReports" \
            -maxdepth 1 -type f \
            \( -iname '*UnicornHostedIMKProbe*' -o -iname '*HostedIMKProbeClient*' -o -iname '*WebDriverAgent*' \) \
            -mmin -20 -print 2>/dev/null | head -10
    )

    /usr/sbin/screencapture -x "$EVIDENCE/desktop-final.png" \
        >"$EVIDENCE/screencapture.stdout" 2>"$EVIDENCE/screencapture.stderr"
    local screenshot_status=$?
    SCREENSHOT_STATUS="$screenshot_status" python3 - "$EVIDENCE/screencapture-result.json" <<'PY'
import datetime as dt
import json
import os
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
image = path.parent / "desktop-final.png"
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "exitCode": int(os.environ["SCREENSHOT_STATUS"]),
    "imagePresent": image.exists(),
    "imageBytes": image.stat().st_size if image.exists() else 0,
}
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY

    truncate_file "$EVIDENCE/appium-full.log" 2097152
    truncate_file "$EVIDENCE/xcodebuild.log" 2097152
    truncate_file "$EVIDENCE/npm-install.log" 1048576
    truncate_file "$EVIDENCE/appium-driver-install.log" 1048576
    truncate_file "$EVIDENCE/system-log.jsonl" 2097152
    truncate_file "$EVIDENCE/processes-final.txt" 262144
    record_phase "evidence-collection" "completed"
    set -e
}

finish() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    if [[ -n "$SELECTION_PID" ]]; then
        if kill -0 "$SELECTION_PID" 2>/dev/null; then
            kill "$SELECTION_PID" 2>/dev/null
        fi
        wait "$SELECTION_PID"
        printf '%s\n' "$?" >"$EVIDENCE/input-source-selection-exit-code.txt"
        SELECTION_PID=""
    fi
    printf '%s\n' "$status" >"$PRODUCER_EXIT_FILE"
    collect_evidence
    "$ROOT/Tests/HostedIMKProbe/cleanup.sh" \
        >"$EVIDENCE/cleanup-command.log" 2>&1
    python3 "$ROOT/Tests/HostedIMKProbe/probe.py" finalize "$EVIDENCE" "$status"
    exit "$status"
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap finish EXIT

record_phase "compile-native-support" "started"
xcrun swiftc \
    -swift-version 5 \
    "$ROOT/Tests/HostedIMKProbe/ProbeHelper.swift" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon \
    -framework CoreGraphics \
    -framework Foundation \
    -framework SystemConfiguration \
    -o "$HELPER"

mkdir -p "$CLIENT_APP/Contents/MacOS"
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
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>HostedIMKProbeClient</string>
    <key>CFBundleIdentifier</key>
    <string>dev.unicorn.hosted-imk-probe.client</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>HostedIMKProbeClient</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.5</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$CLIENT_APP"
record_phase "compile-native-support" "completed"

record_phase "runner-preflight" "started"
python3 "$ROOT/Tests/HostedIMKProbe/probe.py" preflight "$EVIDENCE" "$HELPER"
record_phase "runner-preflight" "completed"

record_phase "build-disposable-unicorn" "started"
if ! xcodebuild \
    -project "$ROOT/unicorn.xcodeproj" \
    -scheme unicorn \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    SYMROOT="$PRODUCTS" \
    OBJROOT="$OBJECTS" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    PRODUCT_BUNDLE_IDENTIFIER="$PROBE_BUNDLE_ID" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    >"$EVIDENCE/xcodebuild.log" 2>&1; then
    record_phase "build-disposable-unicorn" "failed"
    exit 1
fi

test -d "$XCODE_APP"
ditto "$XCODE_APP" "$BUILT_APP"
mv "$BUILT_APP/Contents/MacOS/unicorn" \
    "$BUILT_APP/Contents/MacOS/$PROBE_EXECUTABLE"
test -f "$BUILT_APP/Contents/Resources/keymap.json"
cmp "$ROOT/unicorn/keymap.json" "$BUILT_APP/Contents/Resources/keymap.json"

python3 - \
    "$BUILT_APP/Contents/Info.plist" \
    "$PROBE_MODE_ID" \
    "$PROBE_EXECUTABLE" <<'PY'
import pathlib
import plistlib
import sys
path = pathlib.Path(sys.argv[1])
mode_id = sys.argv[2]
executable = sys.argv[3]
with path.open("rb") as handle:
    info = plistlib.load(handle)
mode_list = info["ComponentInputModeDict"]["tsInputModeListKey"]
settings = next(iter(mode_list.values()))
info["ComponentInputModeDict"]["tsInputModeListKey"] = {mode_id: settings}
info["CFBundleExecutable"] = executable
info["CFBundleName"] = executable
with path.open("wb") as handle:
    plistlib.dump(info, handle, sort_keys=False)
PY

cat >"$BUILD_ROOT/probe.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-register.global-name</key>
    <array>
        <string>${PROBE_BUNDLE_ID}_Connection</string>
    </array>
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements "$BUILD_ROOT/probe.entitlements" "$BUILT_APP"
codesign --verify --deep --strict --verbose=4 "$BUILT_APP"
python3 "$ROOT/Tests/HostedIMKProbe/probe.py" record-build \
    "$EVIDENCE" "$BUILT_APP" "$CLIENT_APP" "$HELPER"
shasum -a 256 "$ROOT/unicorn/keymap.json" "$BUILT_APP/Contents/Resources/keymap.json" \
    >"$EVIDENCE/keymap-sha256.txt"
record_phase "build-disposable-unicorn" "completed"

record_phase "install-appium" "started"
npm install --global appium@3.7.0 --no-audit --no-fund \
    >"$EVIDENCE/npm-install.log" 2>&1
appium driver install mac2@4.2.0 \
    >"$EVIDENCE/appium-driver-install.log" 2>&1
appium driver doctor mac2 \
    >"$EVIDENCE/appium-doctor.log" 2>&1 || true
appium --version >"$EVIDENCE/appium-version.txt"
appium driver list --installed >"$EVIDENCE/appium-drivers.txt"
record_phase "install-appium" "completed"

record_phase "register-and-select-input-source" "started"
if [[ -e "$INSTALLED_APP" ]]; then
    echo "Refusing to replace pre-existing disposable probe app: $INSTALLED_APP" >&2
    record_phase "register-and-select-input-source" "failed-existing-path"
    exit 1
fi
mkdir -p "$(dirname "$INSTALLED_APP")"
ditto "$BUILT_APP" "$INSTALLED_APP"
"$HELPER" install-select \
    "$INSTALLED_APP" \
    "$PROBE_BUNDLE_ID" \
    "$PROBE_MODE_ID" \
    "$EVIDENCE/input-source-state.json" \
    "$EVIDENCE/input-source-selection.json" \
    >"$EVIDENCE/input-source-selection-command.log" 2>&1 &
SELECTION_PID=$!
record_phase "register-and-select-input-source" "helper-started"

record_phase "appium-inputmethodkit-probe" "started"
python3 "$ROOT/Tests/HostedIMKProbe/probe.py" run \
    "$EVIDENCE" \
    "$CLIENT_APP" \
    "$HELPER" \
    "$PROBE_BUNDLE_ID" \
    "$PROBE_MODE_ID" \
    "$PROBE_EXECUTABLE"
record_phase "appium-inputmethodkit-probe" "completed"
