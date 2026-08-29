#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedIMKProbe"
EVIDENCE="$BUILD_ROOT/evidence"
HELPER="$BUILD_ROOT/bin/ProbeHelper"
STATE="$EVIDENCE/input-source-state.json"
RESULT="$EVIDENCE/cleanup.json"
PROBE_BUNDLE_ID="dev.unicorn.inputmethod.hosted-imk-probe"
PROBE_MODE_ID="dev.unicorn.inputmethod.hosted-imk-probe.mode"
INSTALLED_APP="$HOME/Library/Input Methods/UnicornHostedIMKProbe.app"

mkdir -p "$EVIDENCE"

if [[ -x "$HELPER" ]]; then
    "$HELPER" cleanup \
        "$STATE" \
        "$PROBE_BUNDLE_ID" \
        "$PROBE_MODE_ID" \
        "$INSTALLED_APP" \
        "$RESULT"
    exit $?
fi

python3 - "$INSTALLED_APP" "$RESULT" <<'PY'
import datetime as dt
import json
import pathlib
import shutil
import sys

app = pathlib.Path(sys.argv[1])
result = pathlib.Path(sys.argv[2])
expected_parent = pathlib.Path.home() / "Library" / "Input Methods"
safe = app.parent == expected_parent and app.name == "UnicornHostedIMKProbe.app"
error = None
if safe and app.exists():
    try:
        shutil.rmtree(app)
    except OSError as exception:
        error = str(exception)
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "success": safe and not app.exists(),
    "nativeHelperAvailable": False,
    "selectionCouldNotHaveStarted": True,
    "safePath": safe,
    "appPath": str(app),
    "appExistsAfter": app.exists(),
    "removeError": error,
}
result.parent.mkdir(parents=True, exist_ok=True)
result.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
sys.exit(0 if value["success"] else 3)
PY
