#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./scripts/release-lib.sh
. "$SCRIPT_DIR/release-lib.sh"

[ "$#" -eq 1 ] || {
    printf 'Usage: %s TAG\n' "$0" >&2
    exit 2
}

release_marketing_version "$1" || release_fail "tag must be vMAJOR.MINOR.PATCH or test-vMAJOR.MINOR.PATCH-NUMBER without leading zeroes"
