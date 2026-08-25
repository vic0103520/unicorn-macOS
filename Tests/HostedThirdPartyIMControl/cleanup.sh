#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedThirdPartyIMControl"
EVIDENCE="$BUILD_ROOT/evidence"
HELPER="$BUILD_ROOT/bin/ThirdPartySourceHelper"
STATE="$EVIDENCE/installation-state.json"
SOURCE_RESULT="$EVIDENCE/source-cleanup.json"
FILE_RESULT="$EVIDENCE/file-cleanup.json"
PROCESS_RESULT="$EVIDENCE/process-cleanup.json"
RESULT="$EVIDENCE/cleanup.json"
mkdir -p "$EVIDENCE"
source_status=0
if [[ -x "$HELPER" && -f "$STATE" ]]; then
    "$HELPER" cleanup-sources "$STATE" "$SOURCE_RESULT" || source_status=$?
else
    python3 - "$STATE" "$SOURCE_RESULT" <<'PY'
import datetime as dt
import json
import pathlib
import sys
state_path = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
try:
    state = json.loads(state_path.read_text())
except (OSError, json.JSONDecodeError):
    state = {}
selection_started = bool(state.get("selectionStarted"))
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "success": not selection_started,
    "nativeHelperAvailable": False,
    "selectionStarted": selection_started,
    "reason": (
        "Selection did not start, so no source restore was needed"
        if not selection_started
        else "Selection started but the native cleanup helper is unavailable"
    ),
}
output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
    source_status=$(python3 - "$SOURCE_RESULT" <<'PY'
import json
import sys
print(0 if json.load(open(sys.argv[1]))["success"] else 4)
PY
)
fi

python3 - "$STATE" "$PROCESS_RESULT" <<'PY'
import datetime as dt
import json
import os
import pathlib
import signal
import subprocess
import sys
import time

state_path = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
try:
    state = json.loads(state_path.read_text())
except (OSError, json.JSONDecodeError):
    state = {}
direct = state.get("directLaunch") or {}
pid = direct.get("pid")
expected = direct.get("executablePath")
result = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "trackedPID": pid,
    "expectedExecutablePath": expected,
    "terminationAttempted": False,
    "forceTerminationAttempted": False,
    "identityMatched": False,
}

def command_for(target):
    completed = subprocess.run(
        ["ps", "-p", str(target), "-o", "command="],
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode, completed.stdout.strip(), completed.stderr

if isinstance(pid, int) and isinstance(expected, str):
    code, command, error = command_for(pid)
    result.update({"commandBefore": command, "psExitCodeBefore": code, "psStderrBefore": error})
    if code != 0:
        result["alreadyAbsent"] = True
    elif command == expected or command.startswith(expected + " "):
        result["identityMatched"] = True
        result["terminationAttempted"] = True
        os.kill(pid, signal.SIGTERM)
        for _ in range(20):
            if command_for(pid)[0] != 0:
                break
            time.sleep(0.1)
        if command_for(pid)[0] == 0:
            result["forceTerminationAttempted"] = True
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.2)
    else:
        result["refusedReason"] = "tracked PID command no longer matches the exact direct-launch executable"
else:
    result["alreadyAbsent"] = True
    result["reason"] = "no direct-launch PID was recorded"

code, command, error = command_for(pid) if isinstance(pid, int) else (1, "", "")
result.update({"psExitCodeAfter": code, "commandAfter": command, "psStderrAfter": error})
result["trackedProcessAbsent"] = code != 0
result["terminatedOnlyExactTrackedProcess"] = (
    result["trackedProcessAbsent"]
    and not result.get("refusedReason")
)
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY

python3 - "$STATE" "$FILE_RESULT" <<'PY'
import datetime as dt
import json
import pathlib
import shutil
import sys
state_path = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
try:
    state = json.loads(state_path.read_text())
except (OSError, json.JSONDecodeError):
    state = {"trackedPaths": []}

home = pathlib.Path.home()
allowed = {
    home / "Library" / "Input Methods" / "Squirrel.app",
    home / "Library" / "Rime",
    home / "Library" / "Preferences" / "im.rime.inputmethod.Squirrel.plist",
    home / "Library" / "Caches" / "im.rime.inputmethod.Squirrel",
    home / "Library" / "Application Support" / "Squirrel",
}
results = []
for item in state.get("trackedPaths", []):
    path = pathlib.Path(item.get("path", ""))
    existed_before = bool(item.get("existedBefore"))
    safe = path in allowed
    removed = False
    error = None
    if safe and not existed_before and path.exists():
        try:
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()
            removed = True
        except OSError as exception:
            error = str(exception)
    results.append({
        "path": str(path),
        "safeAllowlistedPath": safe,
        "existedBefore": existed_before,
        "removed": removed,
        "existsAfter": path.exists(),
        "error": error,
    })
success = bool(results) and all(
    item["safeAllowlistedPath"]
    and (item["existedBefore"] or not item["existsAfter"])
    and item["error"] is None
    for item in results
)
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "success": success,
    "removedOnlyTrackedNonPreexistingSquirrelPaths": success,
    "paths": results,
}
output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY

if [[ -x "$HELPER" ]]; then
    "$HELPER" sources "after-cleanup" \
        "$EVIDENCE/input-sources-after-cleanup.json" \
        >"$EVIDENCE/input-sources-after-cleanup-command.log" 2>&1 || true
fi

python3 - "$SOURCE_RESULT" "$FILE_RESULT" "$PROCESS_RESULT" "$RESULT" "$source_status" <<'PY'
import datetime as dt
import json
import pathlib
import subprocess
import sys

def load(path):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        return {"present": False, "success": False}

source = load(sys.argv[1])
files = load(sys.argv[2])
exact_process = load(sys.argv[3])
process = subprocess.run(
    ["pgrep", "-x", "Squirrel"], capture_output=True, text=True, check=False
)
process_absent = process.returncode == 1
success = (
    int(sys.argv[5]) == 0
    and bool(source.get("success"))
    and bool(files.get("success"))
    and bool(exact_process.get("terminatedOnlyExactTrackedProcess"))
    and process_absent
)
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "success": success,
    "restoredOriginalSourceAndDisabledThirdPartySources": source,
    "removedTemporaryThirdPartyState": files,
    "exactDirectLaunchProcessCleanup": exact_process,
    "squirrelProcessAbsent": process_absent,
    "pgrepExitCode": process.returncode,
    "pgrepStdout": process.stdout,
}
path = pathlib.Path(sys.argv[4])
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
raise SystemExit(0 if success else 5)
PY
