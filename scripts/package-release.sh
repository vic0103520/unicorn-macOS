#!/bin/sh
set -eu
export COPYFILE_DISABLE=1

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./scripts/release-lib.sh
. "$SCRIPT_DIR/release-lib.sh"

usage() {
    printf 'Usage: %s TAG BUILD_NUMBER APP_BUNDLE OUTPUT_DIR\n' "$0" >&2
    exit 2
}

[ "$#" -eq 4 ] || usage
TAG=$1
BUILD_NUMBER=$2
APP_BUNDLE=$3
OUTPUT_DIR=$4

MARKETING_VERSION=$(release_marketing_version "$TAG") || {
    release_fail "tag must be vMAJOR.MINOR.PATCH or test-vMAJOR.MINOR.PATCH-NUMBER without leading zeroes"
}
release_validate_build_number "$BUILD_NUMBER" || release_fail "build number must be a positive decimal integer"
release_validate_app "$APP_BUNDLE" "$MARKETING_VERSION" "$BUILD_NUMBER" || exit 1

/bin/mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH='' cd -- "$OUTPUT_DIR" && pwd -P)
ARCHIVE_PATH="$OUTPUT_DIR/$RELEASE_ARCHIVE_NAME"
ARCHIVE_SUMS_PATH="$OUTPUT_DIR/$RELEASE_ARCHIVE_SUMS_NAME"
EXECUTABLE_SUM_PATH="$OUTPUT_DIR/$RELEASE_EXECUTABLE_SUM_NAME"
NOTES_PATH="$OUTPUT_DIR/$RELEASE_NOTES_NAME"

WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unicorn-release.XXXXXX") || release_fail "unable to create release staging directory"
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    /bin/rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

PAYLOAD_DIR="$WORK_DIR/payload"
/bin/mkdir "$PAYLOAD_DIR"
/usr/bin/ditto "$APP_BUNDLE" "$PAYLOAD_DIR/$RELEASE_APP_NAME"
/bin/cp "$SCRIPT_DIR/../install.sh" "$PAYLOAD_DIR/install.sh"
/bin/chmod 755 "$PAYLOAD_DIR/install.sh"

EXECUTABLE_SUM=$(release_sha256 "$PAYLOAD_DIR/$RELEASE_EXECUTABLE_PATH")
printf '%s  %s\n' "$EXECUTABLE_SUM" "$RELEASE_EXECUTABLE_PATH" > "$PAYLOAD_DIR/$RELEASE_EXECUTABLE_SUM_NAME"
/bin/cp "$PAYLOAD_DIR/$RELEASE_EXECUTABLE_SUM_NAME" "$EXECUTABLE_SUM_PATH"

cat > "$PAYLOAD_DIR/$RELEASE_METADATA_NAME" <<EOF
{
  "schemaVersion": 1,
  "tag": "$TAG",
  "marketingVersion": "$MARKETING_VERSION",
  "buildNumber": "$BUILD_NUMBER",
  "bundleIdentifier": "$RELEASE_BUNDLE_IDENTIFIER",
  "archiveName": "$RELEASE_ARCHIVE_NAME",
  "executablePath": "$RELEASE_EXECUTABLE_PATH",
  "executableSHA256": "$EXECUTABLE_SUM"
}
EOF
/usr/bin/plutil -p "$PAYLOAD_DIR/$RELEASE_METADATA_NAME" >/dev/null

# ZIP stores file modification times, so normalize a private copy and feed entries
# in lexical order. This makes repeated packaging of identical bundle bytes stable.
/usr/bin/find "$PAYLOAD_DIR" -exec /usr/bin/touch -h -t 198001010000 {} +
ARCHIVE_TEMP="$WORK_DIR/$RELEASE_ARCHIVE_NAME"
(
    cd "$PAYLOAD_DIR"
    LC_ALL=C /usr/bin/find . -mindepth 1 -print |
        /usr/bin/sed 's|^\./||' |
        LC_ALL=C /usr/bin/sort |
        /usr/bin/zip -X -q -y "$ARCHIVE_TEMP" -@
)
/bin/mv -f "$ARCHIVE_TEMP" "$ARCHIVE_PATH"

ARCHIVE_SUM=$(release_sha256 "$ARCHIVE_PATH")
printf '%s  %s\n' "$ARCHIVE_SUM" "$RELEASE_ARCHIVE_NAME" > "$ARCHIVE_SUMS_PATH"
release_write_notes "$TAG" "$MARKETING_VERSION" "$BUILD_NUMBER" "$ARCHIVE_SUM" "$EXECUTABLE_SUM" "$NOTES_PATH"

/bin/rm -rf "$WORK_DIR" || release_fail "release staging cleanup failed: $WORK_DIR"
trap - EXIT HUP INT TERM
printf 'Release artifacts ready: tag=%s version=%s build=%s archive=%s\n' \
    "$TAG" "$MARKETING_VERSION" "$BUILD_NUMBER" "$ARCHIVE_PATH"
