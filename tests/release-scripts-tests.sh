#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./tests/shell-test-lib.sh
. "$SCRIPT_DIR/shell-test-lib.sh"

WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unicorn-release-tests.XXXXXX")
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

APP_PATH="$WORK_DIR/fixture app/unicorn.app"
DIST_PATH="$WORK_DIR/release assets"
create_test_app "$APP_PATH" 1.2.3 42 release-fixture
"$TEST_ROOT_DIR/scripts/package-release.sh" v1.2.3 42 "$APP_PATH" "$DIST_PATH" >/dev/null
"$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$DIST_PATH" '' "$DIST_PATH/RELEASE_NOTES.md" >/dev/null
pass 'final release archive and rendered metadata verify'

ARCHIVE_SUM=$(/usr/bin/shasum -a 256 "$DIST_PATH/unicorn-macos.zip" | /usr/bin/awk '{print $1}')
assert_contains "$DIST_PATH/SHA256SUMS" "$ARCHIVE_SUM  unicorn-macos.zip"
assert_contains "$DIST_PATH/RELEASE_NOTES.md" "$ARCHIVE_SUM  unicorn-macos.zip"
# shellcheck disable=SC2016 # This assertion searches for literal command substitution text.
assert_not_contains "$DIST_PATH/RELEASE_NOTES.md" '$('
pass 'release notes contain the exact final archive digest, not shell text'

SECOND_DIST="$WORK_DIR/repeated assets"
"$TEST_ROOT_DIR/scripts/package-release.sh" v1.2.3 42 "$APP_PATH" "$SECOND_DIST" >/dev/null
/usr/bin/cmp -s "$DIST_PATH/unicorn-macos.zip" "$SECOND_DIST/unicorn-macos.zip" || fail_test 'repeated archive bytes differ'
/usr/bin/cmp -s "$DIST_PATH/SHA256SUMS" "$SECOND_DIST/SHA256SUMS" || fail_test 'repeated archive manifests differ'
/usr/bin/cmp -s "$DIST_PATH/UNICORN_EXECUTABLE_SHA256" "$SECOND_DIST/UNICORN_EXECUTABLE_SHA256" || fail_test 'repeated executable manifests differ'
/usr/bin/cmp -s "$DIST_PATH/RELEASE_NOTES.md" "$SECOND_DIST/RELEASE_NOTES.md" || fail_test 'repeated release notes differ'
pass 'packaging identical app bytes is deterministic'

for malformed_tag in v1 v1.2 v1.2.3.4 v01.2.3 v1.02.3 v1.2.03 v1.2.3-beta test-v1.2.3 test-v1.2.3-name release-v1.2.3; do
    expect_failure "malformed tag rejected: $malformed_tag" "$TEST_ROOT_DIR/scripts/release-version.sh" "$malformed_tag"
done
expect_failure 'zero build number rejected' "$TEST_ROOT_DIR/scripts/package-release.sh" v1.2.3 0 "$APP_PATH" "$WORK_DIR/invalid-build"
expect_failure 'tag and bundle marketing version mismatch rejected' "$TEST_ROOT_DIR/scripts/package-release.sh" v1.2.4 42 "$APP_PATH" "$WORK_DIR/version-mismatch"
expect_failure 'CI build number and bundle build mismatch rejected' "$TEST_ROOT_DIR/scripts/package-release.sh" v1.2.3 43 "$APP_PATH" "$WORK_DIR/build-mismatch"
expect_failure 'existing production tag is never reused' /usr/bin/make -C "$TEST_ROOT_DIR" --no-print-directory _push_release_tag TAG=v0.1.2

MISSING_ASSET="$WORK_DIR/missing asset"
copy_release_assets "$DIST_PATH" "$MISSING_ASSET"
/bin/rm "$MISSING_ASSET/SHA256SUMS"
expect_failure 'missing checksum asset rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$MISSING_ASSET"

MALFORMED_SUM="$WORK_DIR/malformed checksum"
copy_release_assets "$DIST_PATH" "$MALFORMED_SUM"
printf '%s *unicorn-macos.zip\nextra\n' "$ARCHIVE_SUM" > "$MALFORMED_SUM/SHA256SUMS"
expect_failure 'malformed checksum file rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$MALFORMED_SUM"

TAMPERED="$WORK_DIR/tampered archive"
copy_release_assets "$DIST_PATH" "$TAMPERED"
printf tampering >> "$TAMPERED/unicorn-macos.zip"
expect_failure 'archive tampering rejected before extraction' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$TAMPERED"

TRUNCATED="$WORK_DIR/truncated archive"
copy_release_assets "$DIST_PATH" "$TRUNCATED"
ARCHIVE_SIZE=$(/usr/bin/stat -f %z "$TRUNCATED/unicorn-macos.zip")
/usr/bin/head -c $((ARCHIVE_SIZE / 2)) "$TRUNCATED/unicorn-macos.zip" > "$TRUNCATED/truncated.zip"
/bin/mv "$TRUNCATED/truncated.zip" "$TRUNCATED/unicorn-macos.zip"
write_archive_sum "$TRUNCATED"
expect_failure 'truncated archive rejected even with a matching outer checksum' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$TRUNCATED"

expect_failure 'requested release version mismatch rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.4 42 "$DIST_PATH"
expect_failure 'requested release build mismatch rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 43 "$DIST_PATH"

MISSING_REQUIRED="$WORK_DIR/missing required file"
copy_release_assets "$DIST_PATH" "$MISSING_REQUIRED"
MISSING_PAYLOAD="$WORK_DIR/missing required payload"
/bin/mkdir "$MISSING_PAYLOAD"
/usr/bin/unzip -q "$MISSING_REQUIRED/unicorn-macos.zip" -d "$MISSING_PAYLOAD"
/bin/rm "$MISSING_PAYLOAD/unicorn.app/Contents/Resources/keymap.json"
rebuild_test_archive "$MISSING_PAYLOAD" "$MISSING_REQUIRED"
expect_failure 'archive missing required app resource rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$MISSING_REQUIRED"

UNSIGNED="$WORK_DIR/unsigned app"
copy_release_assets "$DIST_PATH" "$UNSIGNED"
UNSIGNED_PAYLOAD="$WORK_DIR/unsigned payload"
/bin/mkdir "$UNSIGNED_PAYLOAD"
/usr/bin/unzip -q "$UNSIGNED/unicorn-macos.zip" -d "$UNSIGNED_PAYLOAD"
/usr/bin/codesign --remove-signature "$UNSIGNED_PAYLOAD/unicorn.app"
UNSIGNED_EXEC_SUM=$(/usr/bin/shasum -a 256 "$UNSIGNED_PAYLOAD/unicorn.app/Contents/MacOS/unicorn" | /usr/bin/awk '{print $1}')
printf '%s  unicorn.app/Contents/MacOS/unicorn\n' "$UNSIGNED_EXEC_SUM" > "$UNSIGNED_PAYLOAD/UNICORN_EXECUTABLE_SHA256"
/bin/cp "$UNSIGNED_PAYLOAD/UNICORN_EXECUTABLE_SHA256" "$UNSIGNED/UNICORN_EXECUTABLE_SHA256"
/usr/bin/plutil -replace executableSHA256 -string "$UNSIGNED_EXEC_SUM" "$UNSIGNED_PAYLOAD/release-metadata.json"
rebuild_test_archive "$UNSIGNED_PAYLOAD" "$UNSIGNED"
expect_failure 'missing ad-hoc app signature rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$UNSIGNED"

METADATA_MISMATCH="$WORK_DIR/metadata mismatch"
copy_release_assets "$DIST_PATH" "$METADATA_MISMATCH"
METADATA_PAYLOAD="$WORK_DIR/metadata mismatch payload"
/bin/mkdir "$METADATA_PAYLOAD"
/usr/bin/unzip -q "$METADATA_MISMATCH/unicorn-macos.zip" -d "$METADATA_PAYLOAD"
/usr/bin/plutil -replace marketingVersion -string 9.9.9 "$METADATA_PAYLOAD/release-metadata.json"
rebuild_test_archive "$METADATA_PAYLOAD" "$METADATA_MISMATCH"
expect_failure 'packaged release metadata mismatch rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$METADATA_MISMATCH"

BAD_NOTES="$WORK_DIR/incorrect release notes.md"
/bin/cp "$DIST_PATH/RELEASE_NOTES.md" "$BAD_NOTES"
printf '\nincorrect checksum text\n' >> "$BAD_NOTES"
expect_failure 'release-note metadata mismatch rejected' "$TEST_ROOT_DIR/scripts/verify-release.sh" v1.2.3 42 "$DIST_PATH" '' "$BAD_NOTES"

printf '[RESULT] Release script tests: passed=%s\n' "$TEST_PASS_COUNT"
