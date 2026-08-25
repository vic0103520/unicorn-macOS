#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BUILD_ROOT="$ROOT/build/HostedBuiltinInputSourceControl"
EVIDENCE="$BUILD_ROOT/evidence"
HELPER="$BUILD_ROOT/bin/BuiltinSourceHelper"
STATE="$EVIDENCE/control-state.json"
RESULT="$EVIDENCE/cleanup-final.json"

mkdir -p "$EVIDENCE"

if [[ -x "$HELPER" && -f "$STATE" ]]; then
    "$HELPER" cleanup "$STATE" "$RESULT"
    exit $?
fi

python3 - "$RESULT" <<'PY'
import datetime as dt
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "success": True,
    "cleanupNeeded": False,
    "reason": "Native helper or control state was not created, so source selection could not start",
}
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
