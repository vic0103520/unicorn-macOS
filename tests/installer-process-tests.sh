#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./tests/shell-test-lib.sh
. "$SCRIPT_DIR/shell-test-lib.sh"

WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unicorn installer process tests.XXXXXX")
FIXTURE_REGISTRY="$WORK_DIR/fixture-pids"
CHILD_REGISTRY="$WORK_DIR/child-pids"
: > "$FIXTURE_REGISTRY"
: > "$CHILD_REGISTRY"
INSTALLER_PID=
WATCHDOG_PID=

pid_executes_path() {
    exact_pid=$1
    exact_path=$2
    [ -e "$exact_path" ] || return 1
    exact_status=0
    exact_output=$(/usr/sbin/lsof -a -d txt -t -p "$exact_pid" -- "$exact_path" 2>/dev/null) || exact_status=$?
    [ "$exact_status" -eq 0 ] || return 1
    printf '%s\n' "$exact_output" | /usr/bin/grep -Eq "^${exact_pid}$"
}

register_fixture() {
    fixture_pid=$1
    fixture_path=$2
    printf '%s|%s\n' "$fixture_pid" "$fixture_path" >> "$FIXTURE_REGISTRY"
}

register_child() {
    printf '%s\n' "$1" >> "$CHILD_REGISTRY"
}

kill_registered_fixtures() {
    while IFS='|' read -r fixture_pid fixture_path; do
        case "$fixture_pid" in ''|*[!0-9]*) continue ;; esac
        # Fixture children remain unreaped until cleanup, so these recorded PIDs
        # cannot be reused even if their executable mapping has been renamed or removed.
        /bin/kill -KILL "$fixture_pid" 2>/dev/null || true
    done < "$FIXTURE_REGISTRY"
}

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    [ -z "$INSTALLER_PID" ] || /bin/kill -TERM "$INSTALLER_PID" 2>/dev/null || true
    [ -z "$WATCHDOG_PID" ] || /bin/kill -TERM "$WATCHDOG_PID" 2>/dev/null || true
    kill_registered_fixtures
    while IFS= read -r child_pid; do
        case "$child_pid" in ''|*[!0-9]*) continue ;; esac
        wait "$child_pid" 2>/dev/null || true
    done < "$CHILD_REGISTRY"
    /bin/rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

PROCESS_SOURCE="$WORK_DIR/process-fixture.c"
cat > "$PROCESS_SOURCE" <<'EOF'
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t terminated = 0;

static void handle_term(int signal_number) {
    (void)signal_number;
    terminated = 1;
}

static int mark_ready(const char *path) {
    int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (descriptor < 0) return 1;
    if (dprintf(descriptor, "%ld\n", (long)getpid()) < 0) return 1;
    return close(descriptor) == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    if (strcmp(argv[1], "ignore") == 0) {
        if (signal(SIGTERM, SIG_IGN) == SIG_ERR) return 3;
    } else {
        if (signal(SIGTERM, handle_term) == SIG_ERR) return 3;
    }
    if (mark_ready(argv[2]) != 0) return 4;
    while (!terminated) pause();
    if (strcmp(argv[1], "delayed") == 0) usleep(350000);
    return 0;
}
EOF

WATCHDOG_SOURCE="$WORK_DIR/watchdog.c"
WATCHDOG_EXECUTABLE="$WORK_DIR/watchdog"
cat > "$WATCHDOG_SOURCE" <<'EOF'
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    pid_t pid = (pid_t)strtol(argv[1], NULL, 10);
    unsigned int seconds = (unsigned int)strtoul(argv[2], NULL, 10);
    sleep(seconds);
    int descriptor = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (descriptor >= 0) close(descriptor);
    return kill(pid, SIGTERM) == 0 ? 0 : 1;
}
EOF
/usr/bin/clang "$WATCHDOG_SOURCE" -o "$WATCHDOG_EXECUTABLE"

create_process_app() {
    process_app_path=$1
    process_version=$2
    process_build=$3
    /bin/mkdir -p "$process_app_path/Contents/MacOS" "$process_app_path/Contents/Resources"
    cat > "$process_app_path/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>unicorn</string>
    <key>CFBundleIdentifier</key>
    <string>Vic-Shih.inputmethod.unicorn</string>
    <key>CFBundleName</key>
    <string>unicorn</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$process_version</string>
    <key>CFBundleVersion</key>
    <string>$process_build</string>
</dict>
</plist>
EOF
    /usr/bin/clang "$PROCESS_SOURCE" -o "$process_app_path/Contents/MacOS/unicorn"
    printf '{}\n' > "$process_app_path/Contents/Resources/keymap.json"
    /usr/bin/codesign --force --sign - "$process_app_path" >/dev/null 2>&1
}

wait_for_file() {
    ready_path=$1
    ready_attempt=0
    while [ "$ready_attempt" -lt 100 ]; do
        [ -f "$ready_path" ] && return 0
        /bin/sleep 0.05
        ready_attempt=$((ready_attempt + 1))
    done
    fail_test "timed out waiting for fixture marker: $ready_path"
}

new_process_case() {
    process_case_name=$1
    PROCESS_CASE_ROOT="$WORK_DIR/$process_case_name"
    PROCESS_HOME="$PROCESS_CASE_ROOT/home"
    PROCESS_DESTINATION="$PROCESS_HOME/Library/Input Methods"
    PROCESS_DISTRIBUTION="$PROCESS_CASE_ROOT/distribution"
    PROCESS_LSREGISTER="$PROCESS_CASE_ROOT/lsregister"
    PROCESS_LS_DB="$PROCESS_CASE_ROOT/launch services db"
    candidate_app="$PROCESS_CASE_ROOT/candidate/unicorn.app"
    old_app="$PROCESS_CASE_ROOT/old/unicorn.app"
    assets="$PROCESS_CASE_ROOT/assets"
    /bin/mkdir -p "$PROCESS_DESTINATION" "$PROCESS_DISTRIBUTION"
    PROCESS_DESTINATION=$(CDPATH='' cd -- "$PROCESS_DESTINATION" && pwd -P)
    create_process_app "$candidate_app" 2.0.0 200
    create_process_app "$old_app" 1.0.0 100
    "$TEST_ROOT_DIR/scripts/package-release.sh" v2.0.0 200 "$candidate_app" "$assets" >/dev/null
    /usr/bin/unzip -q "$assets/unicorn-macos.zip" -d "$PROCESS_DISTRIBUTION"
    /usr/bin/ditto "$old_app" "$PROCESS_DESTINATION/unicorn.app"
    make_fake_launch_services "$PROCESS_LSREGISTER"
}

launch_old_fixture() {
    fixture_mode=$1
    fixture_ready=$2
    fixture_executable="$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn"
    [ -z "$(/usr/sbin/lsof -a -d txt -t -- "$fixture_executable" 2>/dev/null || true)" ] || \
        fail_test "pre-existing process executes fixture: $fixture_executable"
    "$fixture_executable" "$fixture_mode" "$fixture_ready" &
    OLD_PID=$!
    register_fixture "$OLD_PID" "$fixture_executable"
    register_child "$OLD_PID"
    wait_for_file "$fixture_ready"
    pid_executes_path "$OLD_PID" "$fixture_executable" || fail_test 'old fixture executable identity was not observed'
}

run_installer_with_watchdog() {
    installer_output=$1
    watchdog_marker=$2
    shift 2
    env \
        HOME="$PROCESS_HOME" \
        UNICORN_ASSUME_YES=1 \
        UNICORN_INSTALL_DIR="$PROCESS_DESTINATION" \
        UNICORN_LSREGISTER_COMMAND="$PROCESS_LSREGISTER" \
        UNICORN_TEST_LS_DB="$PROCESS_LS_DB" \
        "$@" \
        /bin/sh "$PROCESS_DISTRIBUTION/install.sh" > "$installer_output" 2>&1 &
    INSTALLER_PID=$!
    register_child "$INSTALLER_PID"
    "$WATCHDOG_EXECUTABLE" "$INSTALLER_PID" 10 "$watchdog_marker" &
    WATCHDOG_PID=$!
    register_child "$WATCHDOG_PID"
    if wait "$INSTALLER_PID"; then
        installer_status=0
    else
        installer_status=$?
    fi
    INSTALLER_PID=
    /bin/kill -TERM "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
    WATCHDOG_PID=
    [ ! -e "$watchdog_marker" ] || fail_test 'installer exceeded the outer watchdog deadline'
    return "$installer_status"
}

assert_installed_version() {
    installed_destination=$1
    expected_version=$2
    actual_version=$(plist_value CFBundleShortVersionString "$installed_destination/unicorn.app/Contents/Info.plist")
    [ "$actual_version" = "$expected_version" ] || fail_test "installed version $actual_version does not match $expected_version"
}

assert_registered_path() {
    expected_path=$1
    actual_path=$(/bin/cat "$PROCESS_LS_DB")
    [ "$actual_path" = "$expected_path" ] || fail_test "registered path $actual_path does not match $expected_path"
}

assert_case_clean() {
    assert_not_exists "$PROCESS_DESTINATION/.unicorn.app.install-staging"
    assert_not_exists "$PROCESS_DESTINATION/.unicorn.app.install-backup"
    assert_not_exists "$PROCESS_DESTINATION/.unicorn.app.install-lock"
}

stop_fixture() {
    stop_pid=$1
    stop_path=$2
    if pid_executes_path "$stop_pid" "$stop_path"; then
        /bin/kill -KILL "$stop_pid"
    fi
    stop_registry="$FIXTURE_REGISTRY.next"
    /usr/bin/awk -F '|' -v stopped="$stop_pid" '$1 != stopped' "$FIXTURE_REGISTRY" > "$stop_registry"
    /bin/mv "$stop_registry" "$FIXTURE_REGISTRY"
    wait "$stop_pid" 2>/dev/null || true
}

new_process_case 'ignored term rollback'
IGNORED_READY="$PROCESS_CASE_ROOT/old-ready"
IGNORED_OUTPUT="$PROCESS_CASE_ROOT/installer-output"
IGNORED_WATCHDOG="$PROCESS_CASE_ROOT/watchdog-fired"
launch_old_fixture ignore "$IGNORED_READY"
if run_installer_with_watchdog "$IGNORED_OUTPUT" "$IGNORED_WATCHDOG" UNICORN_TEST_TERMINATION_ATTEMPTS=20; then
    fail_test 'SIGTERM-ignoring old process unexpectedly allowed installation'
fi
assert_contains "$IGNORED_OUTPUT" 'unable to terminate the previous Unicorn process within the grace period'
assert_contains "$IGNORED_OUTPUT" 'Previous Unicorn installation restored.'
assert_not_contains "$IGNORED_OUTPUT" 'Success:'
assert_installed_version "$PROCESS_DESTINATION" 1.0.0
assert_registered_path "$PROCESS_DESTINATION/unicorn.app"
pid_executes_path "$OLD_PID" "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn" || \
    fail_test 'rollback did not preserve the original ignored-TERM identity'
assert_case_clean
stop_fixture "$OLD_PID" "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn"
pass 'ignored SIGTERM fails the upgrade, restores the old app, and suppresses success'

new_process_case 'delayed graceful exit'
DELAYED_READY="$PROCESS_CASE_ROOT/old-ready"
DELAYED_OUTPUT="$PROCESS_CASE_ROOT/installer-output"
DELAYED_WATCHDOG="$PROCESS_CASE_ROOT/watchdog-fired"
launch_old_fixture delayed "$DELAYED_READY"
run_installer_with_watchdog "$DELAYED_OUTPUT" "$DELAYED_WATCHDOG" UNICORN_TEST_TERMINATION_ATTEMPTS=30
assert_contains "$DELAYED_OUTPUT" 'Success: Unicorn 2.0.0 (build 200) was installed and registered'
assert_installed_version "$PROCESS_DESTINATION" 2.0.0
assert_registered_path "$PROCESS_DESTINATION/unicorn.app"
if pid_executes_path "$OLD_PID" "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn" || \
    pid_executes_path "$OLD_PID" "$PROCESS_DESTINATION/.unicorn.app.install-backup/Contents/MacOS/unicorn"; then
    fail_test 'delayed old identity still executes a fixture executable'
fi
assert_case_clean
pass 'delayed graceful termination exits within the bound and allows upgrade'

new_process_case 'replacement identity'
RELAUNCH_READY="$PROCESS_CASE_ROOT/old-ready"
REPLACEMENT_READY="$PROCESS_CASE_ROOT/replacement-ready"
RELAUNCH_OUTPUT="$PROCESS_CASE_ROOT/installer-output"
RELAUNCH_WATCHDOG="$PROCESS_CASE_ROOT/watchdog-fired"
launch_old_fixture delayed "$RELAUNCH_READY"
(
    old_backup="$PROCESS_DESTINATION/.unicorn.app.install-backup/Contents/MacOS/unicorn"
    while [ ! -e "$old_backup" ]; do
        /bin/sleep 0.05
    done
    while pid_executes_path "$OLD_PID" "$old_backup"; do
        /bin/sleep 0.05
    done
    exec "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn" replacement "$REPLACEMENT_READY"
) &
REPLACEMENT_PID=$!
register_fixture "$REPLACEMENT_PID" "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn"
register_child "$REPLACEMENT_PID"
run_installer_with_watchdog "$RELAUNCH_OUTPUT" "$RELAUNCH_WATCHDOG" UNICORN_TEST_TERMINATION_ATTEMPTS=30
wait_for_file "$REPLACEMENT_READY"
pid_executes_path "$REPLACEMENT_PID" "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn" || \
    fail_test 'replacement fixture identity was not observed'
assert_contains "$RELAUNCH_OUTPUT" 'Success: Unicorn 2.0.0 (build 200) was installed and registered'
assert_installed_version "$PROCESS_DESTINATION" 2.0.0
assert_case_clean
stop_fixture "$REPLACEMENT_PID" "$PROCESS_DESTINATION/unicorn.app/Contents/MacOS/unicorn"
pass 'replacement launched after old exit is not mistaken for an old survivor'

printf '[RESULT] Installer process tests: passed=%s\n' "$TEST_PASS_COUNT"
