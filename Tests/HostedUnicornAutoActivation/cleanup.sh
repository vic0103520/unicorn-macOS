#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedUnicornAutoActivation"
EVIDENCE="$BUILD_ROOT/evidence"
HELPER="$BUILD_ROOT/bin/UnicornSourceHelper"
STATE="$EVIDENCE/installation-state.json"
SOURCE_RESULT="$EVIDENCE/source-cleanup.json"
PROCESS_RESULT="$EVIDENCE/process-cleanup.json"
FILE_RESULT="$EVIDENCE/file-cleanup.json"
RESULT="$EVIDENCE/cleanup.json"
mkdir -p "$EVIDENCE"

source_status=0
if [[ -x "$HELPER" && -f "$STATE" ]]; then
    "$HELPER" cleanup "$STATE" "$SOURCE_RESULT" || source_status=$?
else
    python3 - "$STATE" "$SOURCE_RESULT" <<'PY'
import datetime as dt
import json
import pathlib
import sys
try:
    state = json.loads(pathlib.Path(sys.argv[1]).read_text())
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
        else "Selection started but the exact native cleanup helper is unavailable"
    ),
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
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

try:
    state = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, json.JSONDecodeError):
    state = {}
tracked = state.get("automaticProcess") or {}
pid = tracked.get("pid")
expected = tracked.get("executablePath")
result = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "trackedPID": pid,
    "expectedExecutablePath": expected,
    "terminationAttempted": False,
    "forceTerminationAttempted": False,
    "identityMatched": False,
}

def identity(target, expected_path):
    ps = subprocess.run(
        ["ps", "-p", str(target), "-o", "pid=,ppid=,uid=,user=,state=,etime=,lstart=,comm=,args="],
        capture_output=True,
        text=True,
        check=False,
    )
    lsof = subprocess.run(
        ["lsof", "-a", "-p", str(target), "-d", "txt", "-Fn"],
        capture_output=True,
        text=True,
        check=False,
    )
    matched = (
        ps.returncode == 0
        and isinstance(expected_path, str)
        and (expected_path in ps.stdout or f"n{expected_path}" in lsof.stdout.splitlines())
    )
    return {
        "present": ps.returncode == 0,
        "matched": matched,
        "psExitCode": ps.returncode,
        "psStdout": ps.stdout,
        "psStderr": ps.stderr,
        "lsofExitCode": lsof.returncode,
        "lsofStdout": lsof.stdout,
        "lsofStderr": lsof.stderr,
    }

if isinstance(pid, int) and isinstance(expected, str):
    before = identity(pid, expected)
    result["before"] = before
    if not before["present"]:
        result["alreadyAbsent"] = True
    elif before["matched"]:
        result["identityMatched"] = True
        result["terminationAttempted"] = True
        os.kill(pid, signal.SIGTERM)
        for _ in range(30):
            if not identity(pid, expected)["present"]:
                break
            time.sleep(0.1)
        if identity(pid, expected)["present"]:
            result["forceTerminationAttempted"] = True
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.2)
    else:
        result["refusedReason"] = "tracked PID no longer maps to the exact installed Unicorn executable"
else:
    result["alreadyAbsent"] = True
    result["reason"] = "no automatically launched Unicorn PID was recorded"

after = identity(pid, expected) if isinstance(pid, int) and isinstance(expected, str) else {"present": False}
result["after"] = after
result["trackedProcessAbsent"] = not after["present"]
result["stoppedOnlyExactExperimentCreatedProcess"] = (
    result["trackedProcessAbsent"] and not result.get("refusedReason")
)
pathlib.Path(sys.argv[2]).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY

python3 - "$STATE" "$FILE_RESULT" <<'PY'
import datetime as dt
import json
import pathlib
import shutil
import sys

try:
    state = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, json.JSONDecodeError):
    state = {"trackedPaths": []}
home = pathlib.Path.home()
allowed = {
    home / "Library" / "Input Methods" / "unicorn.app",
    home / "Library" / "Containers" / "Vic-Shih.inputmethod.unicorn",
    home / "Library" / "Preferences" / "Vic-Shih.inputmethod.unicorn.plist",
    home / "Library" / "Caches" / "Vic-Shih.inputmethod.unicorn",
    home / "Library" / "Application Support" / "Unicorn",
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
    "removedOnlyTrackedNonPreexistingState": success,
    "paths": results,
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY

if [[ -x "$HELPER" ]]; then
    "$HELPER" sources "after-cleanup" "$EVIDENCE/input-sources-after-cleanup.json" \
        >"$EVIDENCE/input-sources-after-cleanup-command.log" 2>&1 || true
fi

python3 - "$SOURCE_RESULT" "$PROCESS_RESULT" "$FILE_RESULT" "$RESULT" "$source_status" <<'PY'
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
process = load(sys.argv[2])
files = load(sys.argv[3])
lookup = subprocess.run(
    ["pgrep", "-x", "unicorn"], capture_output=True, text=True, check=False
)
process_absent = lookup.returncode == 1
success = (
    int(sys.argv[5]) == 0
    and source.get("success") is True
    and process.get("stoppedOnlyExactExperimentCreatedProcess") is True
    and files.get("success") is True
    and process_absent
)
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "success": success,
    "restoredInitialSourceAndEnablement": source,
    "exactProcessCleanup": process,
    "removedTrackedNonPreexistingState": files,
    "unicornProcessAbsent": process_absent,
    "pgrepExitCode": lookup.returncode,
    "pgrepStdout": lookup.stdout,
    "pgrepStderr": lookup.stderr,
}
pathlib.Path(sys.argv[4]).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
raise SystemExit(0 if success else 5)
PY
