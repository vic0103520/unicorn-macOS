#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./tests/shell-test-lib.sh
. "$SCRIPT_DIR/shell-test-lib.sh"

WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unicorn installer tests.XXXXXX")
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

CANDIDATE_APP="$WORK_DIR/candidate source/unicorn.app"
RELEASE_ASSETS="$WORK_DIR/release assets"
BASE_DISTRIBUTION="$WORK_DIR/base distribution"
FAKE_LSREGISTER="$WORK_DIR/fake lsregister"
create_test_app "$CANDIDATE_APP" 2.0.0 200 candidate
"$TEST_ROOT_DIR/scripts/package-release.sh" v2.0.0 200 "$CANDIDATE_APP" "$RELEASE_ASSETS" >/dev/null
/bin/mkdir "$BASE_DISTRIBUTION"
/usr/bin/unzip -q "$RELEASE_ASSETS/unicorn-macos.zip" -d "$BASE_DISTRIBUTION"
make_fake_launch_services "$FAKE_LSREGISTER"

new_distribution() {
    case_name=$1
    case_distribution="$WORK_DIR/$case_name/distribution"
    /bin/mkdir -p "$case_distribution"
    /usr/bin/ditto "$BASE_DISTRIBUTION" "$case_distribution"
    printf '%s\n' "$case_distribution"
}

new_destination() {
    case_name=$1
    case_destination="$WORK_DIR/$case_name/home with spaces/Library/Input Methods"
    /bin/mkdir -p "$case_destination"
    printf '%s\n' "$case_destination"
}

install_old_app() {
    old_destination=$1
    old_source="$WORK_DIR/old-$TEST_PASS_COUNT/unicorn.app"
    create_test_app "$old_source" 1.0.0 100 previous
    /usr/bin/ditto "$old_source" "$old_destination/unicorn.app"
}

run_installer() {
    distribution=$1
    destination=$2
    output=$3
    shift 3
    env \
        UNICORN_ASSUME_YES=1 \
        UNICORN_INSTALL_DIR="$destination" \
        UNICORN_LSREGISTER_COMMAND="$FAKE_LSREGISTER" \
        UNICORN_TEST_LS_DB="$destination/launch services db" \
        "$@" \
        /bin/sh "$distribution/install.sh" > "$output" 2>&1
}

assert_installed_version() {
    installed_destination=$1
    expected_version=$2
    actual_version=$(plist_value CFBundleShortVersionString "$installed_destination/unicorn.app/Contents/Info.plist")
    [ "$actual_version" = "$expected_version" ] || fail_test "installed version $actual_version does not match $expected_version"
}

assert_transaction_clean() {
    clean_destination=$1
    assert_not_exists "$clean_destination/.unicorn.app.install-staging"
    assert_not_exists "$clean_destination/.unicorn.app.install-backup"
    assert_not_exists "$clean_destination/.unicorn.app.install-lock"
}

FIRST_DISTRIBUTION=$(new_distribution 'first install')
FIRST_DESTINATION=$(new_destination 'first install')
FIRST_OUTPUT="$WORK_DIR/first install/output"
/usr/bin/xattr -w com.apple.quarantine 'test' "$FIRST_DISTRIBUTION/unicorn.app"
run_installer "$FIRST_DISTRIBUTION" "$FIRST_DESTINATION" "$FIRST_OUTPUT"
assert_installed_version "$FIRST_DESTINATION" 2.0.0
assert_contains "$FIRST_OUTPUT" 'Success: Unicorn 2.0.0 (build 200) was installed and registered'
if /usr/bin/xattr -r "$FIRST_DESTINATION/unicorn.app" 2>/dev/null | /usr/bin/grep -Fq com.apple.quarantine; then
    fail_test 'quarantine remained after first install'
fi
assert_transaction_clean "$FIRST_DESTINATION"
pass 'first install validates, stages, registers, and reports success'

UPGRADE_DISTRIBUTION=$(new_distribution 'upgrade path with spaces')
UPGRADE_DESTINATION=$(new_destination 'upgrade path with spaces')
install_old_app "$UPGRADE_DESTINATION"
UPGRADE_OUTPUT="$WORK_DIR/upgrade path with spaces/output"
run_installer "$UPGRADE_DISTRIBUTION" "$UPGRADE_DESTINATION" "$UPGRADE_OUTPUT"
assert_installed_version "$UPGRADE_DESTINATION" 2.0.0
assert_transaction_clean "$UPGRADE_DESTINATION"
pass 'upgrade with spaces replaces a validated previous installation transactionally'

REGISTRATION_DISTRIBUTION=$(new_distribution 'registration failure')
REGISTRATION_DESTINATION=$(new_destination 'registration failure')
install_old_app "$REGISTRATION_DESTINATION"
REGISTRATION_OUTPUT="$WORK_DIR/registration failure/output"
if run_installer "$REGISTRATION_DISTRIBUTION" "$REGISTRATION_DESTINATION" "$REGISTRATION_OUTPUT" UNICORN_TEST_LS_FAIL_VERSION=2.0.0; then
    fail_test 'registration failure unexpectedly succeeded'
fi
assert_not_contains "$REGISTRATION_OUTPUT" 'Success:'
assert_contains "$REGISTRATION_OUTPUT" 'Previous Unicorn installation restored.'
assert_installed_version "$REGISTRATION_DESTINATION" 1.0.0
assert_transaction_clean "$REGISTRATION_DESTINATION"
pass 'registration command failure restores the previous installation without success'

POSTCONDITION_DISTRIBUTION=$(new_distribution 'registration postcondition failure')
POSTCONDITION_DESTINATION=$(new_destination 'registration postcondition failure')
install_old_app "$POSTCONDITION_DESTINATION"
POSTCONDITION_OUTPUT="$WORK_DIR/registration postcondition failure/output"
if run_installer "$POSTCONDITION_DISTRIBUTION" "$POSTCONDITION_DESTINATION" "$POSTCONDITION_OUTPUT" UNICORN_TEST_LS_OMIT_VERSION=2.0.0; then
    fail_test 'registration postcondition failure unexpectedly succeeded'
fi
assert_not_contains "$POSTCONDITION_OUTPUT" 'Success:'
assert_installed_version "$POSTCONDITION_DESTINATION" 1.0.0
assert_transaction_clean "$POSTCONDITION_DESTINATION"
pass 'unmet registration postcondition restores the previous installation'

FIRST_FAILURE_DISTRIBUTION=$(new_distribution 'failed first registration')
FIRST_FAILURE_DESTINATION=$(new_destination 'failed first registration')
FIRST_FAILURE_OUTPUT="$WORK_DIR/failed first registration/output"
if run_installer "$FIRST_FAILURE_DISTRIBUTION" "$FIRST_FAILURE_DESTINATION" "$FIRST_FAILURE_OUTPUT" UNICORN_TEST_LS_FAIL_VERSION=2.0.0; then
    fail_test 'failed first registration unexpectedly succeeded'
fi
assert_not_exists "$FIRST_FAILURE_DESTINATION/unicorn.app"
assert_not_contains "$FIRST_FAILURE_OUTPUT" 'Success:'
assert_transaction_clean "$FIRST_FAILURE_DESTINATION"
pass 'failed first install removes the incomplete candidate'

FAILING_MOVE="$WORK_DIR/fail staged replacement"
cat > "$FAILING_MOVE" <<'EOF'
#!/bin/sh
set -eu
case $1 in
    */.unicorn.app.install-staging)
        if [ ! -f "${UNICORN_TEST_MOVE_STATE:?}" ]; then
            : > "$UNICORN_TEST_MOVE_STATE"
            exit 44
        fi
        ;;
esac
exec /bin/mv "$@"
EOF
/bin/chmod 755 "$FAILING_MOVE"
REPLACEMENT_DISTRIBUTION=$(new_distribution 'replacement failure')
REPLACEMENT_DESTINATION=$(new_destination 'replacement failure')
install_old_app "$REPLACEMENT_DESTINATION"
REPLACEMENT_OUTPUT="$WORK_DIR/replacement failure/output"
if run_installer "$REPLACEMENT_DISTRIBUTION" "$REPLACEMENT_DESTINATION" "$REPLACEMENT_OUTPUT" \
    UNICORN_MOVE_COMMAND="$FAILING_MOVE" UNICORN_TEST_MOVE_STATE="$WORK_DIR/replacement failure/move state"; then
    fail_test 'replacement failure unexpectedly succeeded'
fi
assert_not_contains "$REPLACEMENT_OUTPUT" 'Success:'
assert_installed_version "$REPLACEMENT_DESTINATION" 1.0.0
assert_transaction_clean "$REPLACEMENT_DESTINATION"
pass 'failed final replacement restores the preserved working installation'

FAILING_COPY="$WORK_DIR/fail copy"
cat > "$FAILING_COPY" <<'EOF'
#!/bin/sh
exit 45
EOF
/bin/chmod 755 "$FAILING_COPY"
COPY_DISTRIBUTION=$(new_distribution 'staging failure')
COPY_DESTINATION=$(new_destination 'staging failure')
install_old_app "$COPY_DESTINATION"
COPY_OUTPUT="$WORK_DIR/staging failure/output"
if run_installer "$COPY_DISTRIBUTION" "$COPY_DESTINATION" "$COPY_OUTPUT" UNICORN_COPY_COMMAND="$FAILING_COPY"; then
    fail_test 'staging failure unexpectedly succeeded'
fi
assert_not_contains "$COPY_OUTPUT" 'Success:'
assert_installed_version "$COPY_DESTINATION" 1.0.0
assert_transaction_clean "$COPY_DESTINATION"
pass 'staging failure leaves the existing installation untouched'

FAILING_XATTR="$WORK_DIR/fail xattr"
cat > "$FAILING_XATTR" <<'EOF'
#!/bin/sh
exit 46
EOF
/bin/chmod 755 "$FAILING_XATTR"
XATTR_DISTRIBUTION=$(new_distribution 'quarantine removal failure')
XATTR_DESTINATION=$(new_destination 'quarantine removal failure')
install_old_app "$XATTR_DESTINATION"
XATTR_OUTPUT="$WORK_DIR/quarantine removal failure/output"
if run_installer "$XATTR_DISTRIBUTION" "$XATTR_DESTINATION" "$XATTR_OUTPUT" UNICORN_XATTR_COMMAND="$FAILING_XATTR"; then
    fail_test 'quarantine removal failure unexpectedly succeeded'
fi
assert_not_contains "$XATTR_OUTPUT" 'Success:'
assert_installed_version "$XATTR_DESTINATION" 1.0.0
assert_transaction_clean "$XATTR_DESTINATION"
pass 'quarantine command failure leaves the destination untouched'

INTERRUPTING_MOVE="$WORK_DIR/interrupt staged replacement"
cat > "$INTERRUPTING_MOVE" <<'EOF'
#!/bin/sh
set -eu
case $1 in
    */.unicorn.app.install-staging)
        /bin/kill -TERM "$PPID"
        /bin/sleep 1
        exit 143
        ;;
esac
exec /bin/mv "$@"
EOF
/bin/chmod 755 "$INTERRUPTING_MOVE"
INTERRUPT_DISTRIBUTION=$(new_distribution 'interrupted replacement')
INTERRUPT_DESTINATION=$(new_destination 'interrupted replacement')
install_old_app "$INTERRUPT_DESTINATION"
INTERRUPT_OUTPUT="$WORK_DIR/interrupted replacement/output"
if run_installer "$INTERRUPT_DISTRIBUTION" "$INTERRUPT_DESTINATION" "$INTERRUPT_OUTPUT" UNICORN_MOVE_COMMAND="$INTERRUPTING_MOVE"; then
    fail_test 'interrupted replacement unexpectedly succeeded'
fi
assert_not_contains "$INTERRUPT_OUTPUT" 'Success:'
assert_installed_version "$INTERRUPT_DESTINATION" 1.0.0
assert_transaction_clean "$INTERRUPT_DESTINATION"
pass 'termination during replacement triggers rollback and cleanup'

STALE_DISTRIBUTION=$(new_distribution 'stale recovery')
STALE_DESTINATION=$(new_destination 'stale recovery')
install_old_app "$STALE_DESTINATION"
/bin/mv "$STALE_DESTINATION/unicorn.app" "$STALE_DESTINATION/.unicorn.app.install-backup"
/usr/bin/ditto "$CANDIDATE_APP" "$STALE_DESTINATION/unicorn.app"
/bin/mkdir "$STALE_DESTINATION/.unicorn.app.install-staging"
printf junk > "$STALE_DESTINATION/.unicorn.app.install-staging/junk"
/bin/mkdir "$STALE_DESTINATION/.unicorn.app.install-lock"
printf '99999999\n' > "$STALE_DESTINATION/.unicorn.app.install-lock/pid"
STALE_OUTPUT="$WORK_DIR/stale recovery/output"
if run_installer "$STALE_DISTRIBUTION" "$STALE_DESTINATION" "$STALE_OUTPUT" UNICORN_COPY_COMMAND="$FAILING_COPY"; then
    fail_test 'post-recovery staging failure unexpectedly succeeded'
fi
assert_contains "$STALE_OUTPUT" 'Recovering an interrupted previous installation...'
assert_installed_version "$STALE_DESTINATION" 1.0.0
assert_transaction_clean "$STALE_DESTINATION"
pass 'stale lock, staging, and backup artifacts recover safely after interruption'

TAMPER_DISTRIBUTION=$(new_distribution 'candidate tampering')
TAMPER_DESTINATION=$(new_destination 'candidate tampering')
install_old_app "$TAMPER_DESTINATION"
printf tampering >> "$TAMPER_DISTRIBUTION/unicorn.app/Contents/MacOS/unicorn"
TAMPER_OUTPUT="$WORK_DIR/candidate tampering/output"
if run_installer "$TAMPER_DISTRIBUTION" "$TAMPER_DESTINATION" "$TAMPER_OUTPUT"; then
    fail_test 'tampered candidate unexpectedly succeeded'
fi
assert_not_contains "$TAMPER_OUTPUT" 'Success:'
assert_contains "$TAMPER_OUTPUT" 'no installation changes were made'
assert_installed_version "$TAMPER_DESTINATION" 1.0.0
assert_transaction_clean "$TAMPER_DESTINATION"
pass 'candidate tampering is rejected before destination changes'

FAILING_LOCK_CLEANUP="$WORK_DIR/fail lock cleanup"
cat > "$FAILING_LOCK_CLEANUP" <<'EOF'
#!/bin/sh
set -eu
case ${2:-} in
    */.unicorn.app.install-lock) exit 47 ;;
esac
exec /bin/rm "$@"
EOF
/bin/chmod 755 "$FAILING_LOCK_CLEANUP"
LOCK_CLEANUP_DISTRIBUTION=$(new_distribution 'lock cleanup failure')
LOCK_CLEANUP_DESTINATION=$(new_destination 'lock cleanup failure')
LOCK_CLEANUP_OUTPUT="$WORK_DIR/lock cleanup failure/output"
if run_installer "$LOCK_CLEANUP_DISTRIBUTION" "$LOCK_CLEANUP_DESTINATION" "$LOCK_CLEANUP_OUTPUT" UNICORN_REMOVE_COMMAND="$FAILING_LOCK_CLEANUP"; then
    fail_test 'lock cleanup failure unexpectedly succeeded'
fi
assert_not_contains "$LOCK_CLEANUP_OUTPUT" 'Success:'
assert_installed_version "$LOCK_CLEANUP_DESTINATION" 2.0.0
/bin/rm -rf "$LOCK_CLEANUP_DESTINATION/.unicorn.app.install-lock"
pass 'cleanup command failure never prints success'

CANCEL_DISTRIBUTION=$(new_distribution 'cancelled install')
CANCEL_DESTINATION=$(new_destination 'cancelled install')
install_old_app "$CANCEL_DESTINATION"
CANCEL_OUTPUT="$WORK_DIR/cancelled install/output"
printf 'n\n' | env \
    UNICORN_INSTALL_DIR="$CANCEL_DESTINATION" \
    UNICORN_LSREGISTER_COMMAND="$FAKE_LSREGISTER" \
    UNICORN_TEST_LS_DB="$CANCEL_DESTINATION/launch services db" \
    /bin/sh "$CANCEL_DISTRIBUTION/install.sh" > "$CANCEL_OUTPUT" 2>&1
assert_contains "$CANCEL_OUTPUT" 'Installation cancelled. No changes were made.'
assert_not_contains "$CANCEL_OUTPUT" 'Success:'
assert_installed_version "$CANCEL_DESTINATION" 1.0.0
assert_transaction_clean "$CANCEL_DESTINATION"
pass 'cancelled installation makes no destination changes'

printf '[RESULT] Installer tests: passed=%s\n' "$TEST_PASS_COUNT"
