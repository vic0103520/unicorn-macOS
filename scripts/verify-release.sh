#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./scripts/release-lib.sh
. "$SCRIPT_DIR/release-lib.sh"

usage() {
    printf 'Usage: %s TAG BUILD_NUMBER ASSET_DIR [EXTRACT_DIR] [RELEASE_BODY]\n' "$0" >&2
    exit 2
}

[ "$#" -ge 3 ] && [ "$#" -le 5 ] || usage
TAG=$1
BUILD_NUMBER=$2
ASSET_DIR=$3
EXTRACT_DIR=${4:-}
RELEASE_BODY=${5:-}

MARKETING_VERSION=$(release_marketing_version "$TAG") || {
    release_fail "tag must be vMAJOR.MINOR.PATCH or test-vMAJOR.MINOR.PATCH-NUMBER without leading zeroes"
}
release_validate_build_number "$BUILD_NUMBER" || release_fail "build number must be a positive decimal integer"
ASSET_DIR=$(CDPATH='' cd -- "$ASSET_DIR" && pwd -P) || release_fail "asset directory does not exist: $ASSET_DIR"

ARCHIVE_PATH="$ASSET_DIR/$RELEASE_ARCHIVE_NAME"
ARCHIVE_SUMS_PATH="$ASSET_DIR/$RELEASE_ARCHIVE_SUMS_NAME"
EXECUTABLE_SUM_PATH="$ASSET_DIR/$RELEASE_EXECUTABLE_SUM_NAME"
for required_asset in "$ARCHIVE_PATH" "$ARCHIVE_SUMS_PATH" "$EXECUTABLE_SUM_PATH"; do
    [ -f "$required_asset" ] && [ ! -L "$required_asset" ] || release_fail "required release asset is missing or unsafe: $required_asset"
done

validate_manifest() {
    manifest_path=$1
    expected_name=$2
    manifest_lines=$(/usr/bin/awk 'END { print NR }' "$manifest_path") || return 1
    [ "$manifest_lines" -eq 1 ] || return 1
    LC_ALL=C /usr/bin/grep -Eq "^[0-9a-f]{64}  $expected_name$" "$manifest_path"
}

validate_manifest "$ARCHIVE_SUMS_PATH" 'unicorn-macos\.zip' || release_fail "$RELEASE_ARCHIVE_SUMS_NAME must contain exactly one conventional archive checksum"
validate_manifest "$EXECUTABLE_SUM_PATH" 'unicorn\.app/Contents/MacOS/unicorn' || release_fail "$RELEASE_EXECUTABLE_SUM_NAME must contain exactly one executable checksum"
(
    cd "$ASSET_DIR"
    /usr/bin/shasum -a 256 -c "$RELEASE_ARCHIVE_SUMS_NAME"
) >/dev/null || release_fail "downloaded archive does not match $RELEASE_ARCHIVE_SUMS_NAME"
/usr/bin/unzip -tqq "$ARCHIVE_PATH" >/dev/null 2>&1 || release_fail "release archive is invalid or truncated"

ENTRY_LIST=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unicorn-zip-entries.XXXXXX") || release_fail "unable to inspect archive"
TEMP_EXTRACT=
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    /bin/rm -f "$ENTRY_LIST"
    if [ -n "$TEMP_EXTRACT" ]; then
        /bin/rm -rf "$TEMP_EXTRACT"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/zipinfo -1 "$ARCHIVE_PATH" > "$ENTRY_LIST" || release_fail "unable to list release archive"
[ -s "$ENTRY_LIST" ] || release_fail "release archive is empty"
if LC_ALL=C /usr/bin/sort "$ENTRY_LIST" | /usr/bin/uniq -d | /usr/bin/grep -q .; then
    release_fail "release archive contains duplicate entries"
fi
while IFS= read -r archive_entry; do
    case "$archive_entry" in
        /*|../*|*/../*|*/..|*\\*)
            release_fail "release archive contains an unsafe path: $archive_entry"
            ;;
    esac
    archive_top_level=${archive_entry%%/*}
    case "$archive_top_level" in
        unicorn.app|install.sh|release-metadata.json|UNICORN_EXECUTABLE_SHA256) ;;
        *) release_fail "release archive contains an unexpected top-level entry: $archive_entry" ;;
    esac
done < "$ENTRY_LIST"

if [ -n "$EXTRACT_DIR" ]; then
    if [ -e "$EXTRACT_DIR" ] || [ -L "$EXTRACT_DIR" ]; then
        release_fail "extraction destination already exists: $EXTRACT_DIR"
    fi
    /bin/mkdir -p "$EXTRACT_DIR"
    EXTRACT_DIR=$(CDPATH='' cd -- "$EXTRACT_DIR" && pwd -P)
else
    TEMP_EXTRACT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unicorn-release-verify.XXXXXX") || release_fail "unable to create verification directory"
    EXTRACT_DIR=$TEMP_EXTRACT
fi
/usr/bin/unzip -q "$ARCHIVE_PATH" -d "$EXTRACT_DIR" || release_fail "unable to extract release archive"

APP_PATH="$EXTRACT_DIR/$RELEASE_APP_NAME"
METADATA_PATH="$EXTRACT_DIR/$RELEASE_METADATA_NAME"
INTERNAL_EXECUTABLE_SUM_PATH="$EXTRACT_DIR/$RELEASE_EXECUTABLE_SUM_NAME"
[ -f "$EXTRACT_DIR/install.sh" ] && [ ! -L "$EXTRACT_DIR/install.sh" ] || release_fail "archive installer is missing or unsafe"
[ -f "$METADATA_PATH" ] && [ ! -L "$METADATA_PATH" ] || release_fail "archive release metadata is missing or unsafe"
[ -f "$INTERNAL_EXECUTABLE_SUM_PATH" ] && [ ! -L "$INTERNAL_EXECUTABLE_SUM_PATH" ] || release_fail "archive executable checksum is missing or unsafe"
/usr/bin/cmp -s "$EXECUTABLE_SUM_PATH" "$INTERNAL_EXECUTABLE_SUM_PATH" || release_fail "downloaded and packaged executable checksums differ"
/usr/bin/plutil -p "$METADATA_PATH" >/dev/null || release_fail "release metadata is malformed"

metadata_schema=$(release_json_value schemaVersion "$METADATA_PATH") || release_fail "release metadata schemaVersion is missing"
metadata_tag=$(release_json_value tag "$METADATA_PATH") || release_fail "release metadata tag is missing"
metadata_version=$(release_json_value marketingVersion "$METADATA_PATH") || release_fail "release metadata marketingVersion is missing"
metadata_build=$(release_json_value buildNumber "$METADATA_PATH") || release_fail "release metadata buildNumber is missing"
metadata_identifier=$(release_json_value bundleIdentifier "$METADATA_PATH") || release_fail "release metadata bundleIdentifier is missing"
metadata_archive=$(release_json_value archiveName "$METADATA_PATH") || release_fail "release metadata archiveName is missing"
metadata_executable_path=$(release_json_value executablePath "$METADATA_PATH") || release_fail "release metadata executablePath is missing"
metadata_executable_sum=$(release_json_value executableSHA256 "$METADATA_PATH") || release_fail "release metadata executableSHA256 is missing"

[ "$metadata_schema" = 1 ] || release_fail "unsupported release metadata schema: $metadata_schema"
[ "$metadata_tag" = "$TAG" ] || release_fail "release metadata tag $metadata_tag does not match $TAG"
[ "$metadata_version" = "$MARKETING_VERSION" ] || release_fail "release metadata version $metadata_version does not match $MARKETING_VERSION"
[ "$metadata_build" = "$BUILD_NUMBER" ] || release_fail "release metadata build $metadata_build does not match $BUILD_NUMBER"
[ "$metadata_identifier" = "$RELEASE_BUNDLE_IDENTIFIER" ] || release_fail "release metadata bundle identifier is incorrect"
[ "$metadata_archive" = "$RELEASE_ARCHIVE_NAME" ] || release_fail "release metadata archive name is incorrect"
[ "$metadata_executable_path" = "$RELEASE_EXECUTABLE_PATH" ] || release_fail "release metadata executable path is incorrect"

manifest_executable_sum=$(/usr/bin/awk '{print $1}' "$EXECUTABLE_SUM_PATH")
[ "$metadata_executable_sum" = "$manifest_executable_sum" ] || release_fail "release metadata executable digest does not match the executable checksum asset"
release_validate_app "$APP_PATH" "$MARKETING_VERSION" "$BUILD_NUMBER" || exit 1
(
    cd "$EXTRACT_DIR"
    /usr/bin/shasum -a 256 -c "$RELEASE_EXECUTABLE_SUM_NAME"
) >/dev/null || release_fail "packaged executable does not match $RELEASE_EXECUTABLE_SUM_NAME"

if [ -n "$RELEASE_BODY" ]; then
    [ -f "$RELEASE_BODY" ] && [ ! -L "$RELEASE_BODY" ] || release_fail "release body file is missing or unsafe"
    EXPECTED_NOTES=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unicorn-release-notes.XXXXXX") || release_fail "unable to create expected release notes"
    ARCHIVE_SUM=$(/usr/bin/awk '{print $1}' "$ARCHIVE_SUMS_PATH")
    release_write_notes "$TAG" "$MARKETING_VERSION" "$BUILD_NUMBER" "$ARCHIVE_SUM" "$manifest_executable_sum" "$EXPECTED_NOTES"
    if ! /usr/bin/cmp -s "$EXPECTED_NOTES" "$RELEASE_BODY"; then
        /bin/rm -f "$EXPECTED_NOTES"
        release_fail "release body does not describe the downloaded assets exactly"
    fi
    /bin/rm -f "$EXPECTED_NOTES"
fi

/bin/rm -f "$ENTRY_LIST" || release_fail "archive inspection cleanup failed"
ENTRY_LIST=
if [ -n "$TEMP_EXTRACT" ]; then
    /bin/rm -rf "$TEMP_EXTRACT" || release_fail "verification staging cleanup failed"
    TEMP_EXTRACT=
fi
trap - EXIT HUP INT TERM
printf 'Release verification succeeded: tag=%s version=%s build=%s archive=%s\n' \
    "$TAG" "$MARKETING_VERSION" "$BUILD_NUMBER" "$ARCHIVE_PATH"
