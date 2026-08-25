#!/bin/sh
set -eu

APP_NAME="unicorn.app"
BUNDLE_IDENTIFIER="Vic-Shih.inputmethod.unicorn"
EXECUTABLE_RELATIVE_PATH="unicorn.app/Contents/MacOS/unicorn"
METADATA_NAME="release-metadata.json"
EXECUTABLE_SUM_NAME="UNICORN_EXECUTABLE_SHA256"
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
APP_PATH="$SCRIPT_DIR/$APP_NAME"
METADATA_PATH="$SCRIPT_DIR/$METADATA_NAME"
EXECUTABLE_SUM_PATH="$SCRIPT_DIR/$EXECUTABLE_SUM_NAME"
INSTALL_DIR=${UNICORN_INSTALL_DIR:-"$HOME/Library/Input Methods"}
LSREGISTER_COMMAND=${UNICORN_LSREGISTER_COMMAND:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}
LSOF_COMMAND=/usr/sbin/lsof
KILL_COMMAND=/bin/kill
COPY_COMMAND=${UNICORN_COPY_COMMAND:-/usr/bin/ditto}
MOVE_COMMAND=${UNICORN_MOVE_COMMAND:-/bin/mv}
REMOVE_COMMAND=${UNICORN_REMOVE_COMMAND:-/bin/rm}
XATTR_COMMAND=${UNICORN_XATTR_COMMAND:-/usr/bin/xattr}

LOCK_HELD=0
REPLACEMENT_ACTIVE=0
BACKUP_CREATED=0
INSTALL_COMMITTED=0
LOCK_PATH=
STAGE_PATH=
BACKUP_PATH=
INSTALLED_PATH=
EXPECTED_VERSION=
EXPECTED_BUILD=
EXPECTED_EXECUTABLE_SUM=
OLD_PROCESS_PIDS=
TERMINATION_ATTEMPTS=${UNICORN_TEST_TERMINATION_ATTEMPTS:-100}
TERMINATION_POLL_SECONDS=0.05

error() {
    printf 'Error: %s\n' "$*" >&2
}

fail() {
    error "$*"
    exit 1
}

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

plist_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$2" 2>/dev/null
}

validate_app() {
    validate_path=$1
    validate_version=$2
    validate_build=$3
    validate_info="$validate_path/Contents/Info.plist"
    validate_executable="$validate_path/Contents/MacOS/unicorn"
    validate_keymap="$validate_path/Contents/Resources/keymap.json"

    [ -d "$validate_path" ] || { error "app bundle is missing: $validate_path"; return 1; }
    [ ! -L "$validate_path" ] || { error "app bundle must not be a symbolic link"; return 1; }
    [ -f "$validate_info" ] || { error "app Info.plist is missing"; return 1; }
    [ -f "$validate_executable" ] && [ -x "$validate_executable" ] || {
        error "app executable is missing or not executable"
        return 1
    }
    [ -f "$validate_keymap" ] || { error "required keymap.json is missing"; return 1; }

    validate_identifier=$(plist_value CFBundleIdentifier "$validate_info") || {
        error "CFBundleIdentifier is missing"
        return 1
    }
    validate_executable_name=$(plist_value CFBundleExecutable "$validate_info") || {
        error "CFBundleExecutable is missing"
        return 1
    }
    validate_marketing=$(plist_value CFBundleShortVersionString "$validate_info") || {
        error "CFBundleShortVersionString is missing"
        return 1
    }
    validate_build_number=$(plist_value CFBundleVersion "$validate_info") || {
        error "CFBundleVersion is missing"
        return 1
    }

    [ "$validate_identifier" = "$BUNDLE_IDENTIFIER" ] || {
        error "unexpected bundle identifier: $validate_identifier"
        return 1
    }
    [ "$validate_executable_name" = unicorn ] || {
        error "unexpected bundle executable: $validate_executable_name"
        return 1
    }
    [ -z "$validate_version" ] || [ "$validate_marketing" = "$validate_version" ] || {
        error "bundle marketing version $validate_marketing does not match $validate_version"
        return 1
    }
    [ -z "$validate_build" ] || [ "$validate_build_number" = "$validate_build" ] || {
        error "bundle build number $validate_build_number does not match $validate_build"
        return 1
    }

    validate_signature=$(/usr/bin/codesign -dv --verbose=4 "$validate_path" 2>&1) || {
        error "unable to inspect app signature"
        return 1
    }
    printf '%s\n' "$validate_signature" | /usr/bin/grep -Fqx 'Signature=adhoc' || {
        error "app does not use the documented ad-hoc signature policy"
        return 1
    }
    printf '%s\n' "$validate_signature" | /usr/bin/grep -Fqx 'TeamIdentifier=not set' || {
        error "ad-hoc app unexpectedly claims an Apple Team ID"
        return 1
    }
    printf '%s\n' "$validate_signature" | /usr/bin/grep -Fqx "Identifier=$BUNDLE_IDENTIFIER" || {
        error "code-signing identifier does not match $BUNDLE_IDENTIFIER"
        return 1
    }
    /usr/bin/codesign --verify --deep --strict "$validate_path" >/dev/null 2>&1 || {
        error "app signature verification failed"
        return 1
    }
}

validate_distribution() {
    [ -f "$METADATA_PATH" ] && [ ! -L "$METADATA_PATH" ] || {
        error "$METADATA_NAME is missing or unsafe"
        return 1
    }
    [ -f "$EXECUTABLE_SUM_PATH" ] && [ ! -L "$EXECUTABLE_SUM_PATH" ] || {
        error "$EXECUTABLE_SUM_NAME is missing or unsafe"
        return 1
    }
    /usr/bin/plutil -p "$METADATA_PATH" >/dev/null || {
        error "$METADATA_NAME is malformed"
        return 1
    }

    distribution_schema=$(plist_value schemaVersion "$METADATA_PATH") || return 1
    distribution_tag=$(plist_value tag "$METADATA_PATH") || return 1
    EXPECTED_VERSION=$(plist_value marketingVersion "$METADATA_PATH") || return 1
    EXPECTED_BUILD=$(plist_value buildNumber "$METADATA_PATH") || return 1
    distribution_identifier=$(plist_value bundleIdentifier "$METADATA_PATH") || return 1
    distribution_archive=$(plist_value archiveName "$METADATA_PATH") || return 1
    distribution_executable=$(plist_value executablePath "$METADATA_PATH") || return 1
    EXPECTED_EXECUTABLE_SUM=$(plist_value executableSHA256 "$METADATA_PATH") || return 1

    [ "$distribution_schema" = 1 ] || { error "unsupported release metadata schema"; return 1; }
    if printf '%s\n' "$distribution_tag" | /usr/bin/grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
        tag_version=${distribution_tag#v}
    elif printf '%s\n' "$distribution_tag" | /usr/bin/grep -Eq '^test-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[0-9]+$'; then
        tag_version=$(printf '%s\n' "${distribution_tag#test-v}" | /usr/bin/sed 's/-[0-9][0-9]*$//')
    else
        error "release metadata tag is malformed: $distribution_tag"
        return 1
    fi
    [ "$EXPECTED_VERSION" = "$tag_version" ] || { error "release tag and marketing version differ"; return 1; }
    case "$EXPECTED_BUILD" in ''|0|*[!0-9]*) error "release build number is malformed"; return 1 ;; esac
    [ "$distribution_identifier" = "$BUNDLE_IDENTIFIER" ] || { error "release bundle identifier is incorrect"; return 1; }
    [ "$distribution_archive" = unicorn-macos.zip ] || { error "release archive name is incorrect"; return 1; }
    [ "$distribution_executable" = "$EXECUTABLE_RELATIVE_PATH" ] || { error "release executable path is incorrect"; return 1; }
    printf '%s\n' "$EXPECTED_EXECUTABLE_SUM" | /usr/bin/grep -Eq '^[0-9a-f]{64}$' || {
        error "release executable digest is malformed"
        return 1
    }

    manifest_lines=$(/usr/bin/awk 'END { print NR }' "$EXECUTABLE_SUM_PATH") || return 1
    if [ "$manifest_lines" -ne 1 ] ||
        ! LC_ALL=C /usr/bin/grep -Eq '^[0-9a-f]{64}  unicorn\.app/Contents/MacOS/unicorn$' "$EXECUTABLE_SUM_PATH"; then
        error "$EXECUTABLE_SUM_NAME is malformed"
        return 1
    fi
    manifest_sum=$(/usr/bin/awk '{print $1}' "$EXECUTABLE_SUM_PATH")
    [ "$manifest_sum" = "$EXPECTED_EXECUTABLE_SUM" ] || {
        error "release metadata and executable checksum differ"
        return 1
    }

    validate_app "$APP_PATH" "$EXPECTED_VERSION" "$EXPECTED_BUILD" || return 1
    actual_sum=$(/usr/bin/shasum -a 256 "$APP_PATH/Contents/MacOS/unicorn" | /usr/bin/awk '{print $1}') || return 1
    [ "$actual_sum" = "$EXPECTED_EXECUTABLE_SUM" ] || {
        error "app executable does not match $EXECUTABLE_SUM_NAME"
        return 1
    }
}

register_app() {
    register_path=$1
    "$LSREGISTER_COMMAND" -f "$register_path" >/dev/null || return 1
    "$LSREGISTER_COMMAND" -dump 2>/dev/null | /usr/bin/awk -v target="$register_path" '
        /^path:[[:space:]]/ {
            value = $0
            sub(/^path:[[:space:]]*/, "", value)
            sub(/ \(0x[0-9A-Fa-f]+\)$/, "", value)
            if (value == target) found = 1
        }
        END { exit(found ? 0 : 1) }
    '
}

inspect_old_executable() {
    inspect_path=$1
    shift
    inspect_error_path="$LOCK_PATH/process-inspection-error"
    if inspect_output=$("$LSOF_COMMAND" -a -d txt -t "$@" -- "$inspect_path" 2>"$inspect_error_path"); then
        inspect_status=0
    else
        inspect_status=$?
    fi

    if [ -s "$inspect_error_path" ] || [ "$inspect_status" -gt 1 ]; then
        return 2
    fi
    case "$inspect_output" in
        '') [ "$inspect_status" -eq 1 ] || return 2 ;;
        *)
            [ "$inspect_status" -eq 0 ] || return 2
            while IFS= read -r inspect_pid; do
                case "$inspect_pid" in ''|*[!0-9]*) return 2 ;; esac
            done <<EOF
$inspect_output
EOF
            ;;
    esac
    printf '%s\n' "$inspect_output"
    return "$inspect_status"
}

snapshot_old_processes() {
    old_executable=$1
    if OLD_PROCESS_PIDS=$(inspect_old_executable "$old_executable"); then
        snapshot_status=0
    else
        snapshot_status=$?
    fi
    [ "$snapshot_status" -eq 0 ] || [ "$snapshot_status" -eq 1 ] || \
        fail "unable to inspect processes executing the previous Unicorn executable"
    [ -z "$OLD_PROCESS_PIDS" ] || OLD_PROCESS_PIDS=$(printf '%s\n' "$OLD_PROCESS_PIDS" | /usr/bin/sort -n -u)
}

old_identity_is_running() {
    identity_pid=$1
    identity_executable=$2
    if identity_output=$(inspect_old_executable "$identity_executable" -p "$identity_pid"); then
        [ "$identity_output" = "$identity_pid" ] || return 2
        return 0
    else
        identity_status=$?
    fi
    [ "$identity_status" -eq 1 ] && return 1
    return 2
}

terminate_old_processes() {
    terminate_executable=$1
    [ -n "$OLD_PROCESS_PIDS" ] || return 0

    for terminate_pid in $OLD_PROCESS_PIDS; do
        if old_identity_is_running "$terminate_pid" "$terminate_executable"; then
            if ! "$KILL_COMMAND" -TERM "$terminate_pid" 2>/dev/null; then
                if old_identity_is_running "$terminate_pid" "$terminate_executable"; then
                    fail "unable to signal a previous Unicorn process (pid $terminate_pid)"
                else
                    signal_inspection_status=$?
                    [ "$signal_inspection_status" -eq 1 ] || fail "unable to inspect a previous Unicorn process after signaling failed"
                fi
            fi
        else
            identity_status=$?
            [ "$identity_status" -eq 1 ] || fail "unable to inspect a previous Unicorn process before signaling"
        fi
    done

    termination_attempt=0
    while [ "$termination_attempt" -lt "$TERMINATION_ATTEMPTS" ]; do
        termination_survivors=
        for terminate_pid in $OLD_PROCESS_PIDS; do
            if old_identity_is_running "$terminate_pid" "$terminate_executable"; then
                termination_survivors="$termination_survivors $terminate_pid"
            else
                identity_status=$?
                [ "$identity_status" -eq 1 ] || fail "unable to inspect a previous Unicorn process while waiting for termination"
            fi
        done
        [ -n "$termination_survivors" ] || return 0
        termination_attempt=$((termination_attempt + 1))
        [ "$termination_attempt" -lt "$TERMINATION_ATTEMPTS" ] || break
        /bin/sleep "$TERMINATION_POLL_SECONDS"
    done
    fail "unable to terminate the previous Unicorn process within the grace period"
}

rollback_installation() {
    printf 'Installation failed; restoring the previous installation...\n' >&2
    if path_exists "$INSTALLED_PATH"; then
        "$REMOVE_COMMAND" -rf "$INSTALLED_PATH" || return 1
    fi
    if [ "$BACKUP_CREATED" -eq 1 ]; then
        "$MOVE_COMMAND" "$BACKUP_PATH" "$INSTALLED_PATH" || return 1
        BACKUP_CREATED=0
        validate_app "$INSTALLED_PATH" '' '' || return 1
        register_app "$INSTALLED_PATH" || return 1
        printf 'Previous Unicorn installation restored.\n' >&2
    else
        printf 'Incomplete first installation removed.\n' >&2
    fi
    REPLACEMENT_ACTIVE=0
}

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    rollback_status=0
    if [ "$status" -ne 0 ] && [ "$REPLACEMENT_ACTIVE" -eq 1 ] && [ "$INSTALL_COMMITTED" -eq 0 ]; then
        rollback_installation || rollback_status=$?
    fi
    if [ -n "$STAGE_PATH" ] && path_exists "$STAGE_PATH"; then
        "$REMOVE_COMMAND" -rf "$STAGE_PATH" || rollback_status=1
    fi
    if [ "$LOCK_HELD" -eq 1 ] && path_exists "$LOCK_PATH"; then
        "$REMOVE_COMMAND" -rf "$LOCK_PATH" || rollback_status=1
    fi
    if [ "$rollback_status" -ne 0 ]; then
        error "automatic recovery was incomplete; the preserved backup is $BACKUP_PATH"
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "$TERMINATION_ATTEMPTS" in
    ''|0|*[!0-9]*) fail "invalid process termination grace-period attempt count" ;;
esac

printf '%s\n' '--------------------------------------------------'
printf '%s\n' 'Unicorn: macOS Installer'
printf '%s\n' '--------------------------------------------------'
printf 'Validating the candidate app and release metadata...\n'
validate_distribution || fail "candidate validation failed; no installation changes were made"
printf 'Candidate validated: version=%s build=%s executable-sha256=%s\n\n' \
    "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$EXPECTED_EXECUTABLE_SUM"

cat <<'EOF'
IMPORTANT SECURITY NOTICE: PLEASE READ CAREFULLY
-----------------------------------------------
You are about to install an unverified Input Method (IM).
This carries significant security and privacy implications:

1. FULL KEYSTROKE ACCESS (KEYLOGGING RISK):
   As an Input Method, Unicorn has the technical capability to
   monitor and record every keystroke you type across applications.

2. LACK OF APPLE NOTARIZATION:
   This application is ad-hoc signed and is not notarized by Apple.
   Apple has not verified the publisher's identity for this build.

3. CORRUPTION OR TAMPERING RISK:
   SHA-256 and the ad-hoc signature check consistency, but neither
   authenticates the publisher when obtained from the same release.

4. DATA EXFILTRATION RISK:
   Any malicious input method could transmit typed data.

BY PROCEEDING, YOU ACKNOWLEDGE THAT:
- You trust the source of this software (vic0103520/unicorn-macOS).
- You assume the risks associated with unverified software.
- The author provides this software "AS IS" without warranties.
-----------------------------------------------
EOF

if [ "${UNICORN_ASSUME_YES:-0}" = 1 ]; then
    response=y
    printf 'Installation confirmation supplied by automation.\n'
else
    printf 'Do you fully understand the risks and wish to install this app? [y/N]: '
    IFS= read -r response || response=
fi
case "$response" in
    [yY][eE][sS]|[yY]) ;;
    *) printf 'Installation cancelled. No changes were made.\n'; exit 0 ;;
esac

printf 'Removing the quarantine attribute from the validated candidate...\n'
"$XATTR_COMMAND" -rd com.apple.quarantine "$APP_PATH" || fail "unable to remove quarantine from the candidate"

/bin/mkdir -p "$INSTALL_DIR" || fail "unable to create installation directory: $INSTALL_DIR"
INSTALL_DIR=$(CDPATH='' cd -- "$INSTALL_DIR" && pwd -P) || fail "unable to resolve installation directory"
INSTALLED_PATH="$INSTALL_DIR/$APP_NAME"
STAGE_PATH="$INSTALL_DIR/.unicorn.app.install-staging"
BACKUP_PATH="$INSTALL_DIR/.unicorn.app.install-backup"
LOCK_PATH="$INSTALL_DIR/.unicorn.app.install-lock"

if ! /bin/mkdir "$LOCK_PATH" 2>/dev/null; then
    lock_pid=
    if [ -f "$LOCK_PATH/pid" ]; then
        lock_pid=$(/bin/cat "$LOCK_PATH/pid" 2>/dev/null || true)
    fi
    case "$lock_pid" in
        ''|*[!0-9]*) fail "another installation or an unsafe lock is present: $LOCK_PATH" ;;
        *)
            if /bin/kill -0 "$lock_pid" 2>/dev/null; then
                fail "another Unicorn installation is already running (pid $lock_pid)"
            fi
            "$REMOVE_COMMAND" -rf "$LOCK_PATH" || fail "unable to remove stale installation lock"
            /bin/mkdir "$LOCK_PATH" || fail "unable to acquire installation lock"
            ;;
    esac
fi
LOCK_HELD=1
printf '%s\n' "$$" > "$LOCK_PATH/pid"

if path_exists "$BACKUP_PATH"; then
    printf 'Recovering an interrupted previous installation...\n'
    validate_app "$BACKUP_PATH" '' '' || fail "preserved installation backup is invalid: $BACKUP_PATH"
    if path_exists "$INSTALLED_PATH"; then
        "$REMOVE_COMMAND" -rf "$INSTALLED_PATH" || fail "unable to remove incomplete installation during recovery"
    fi
    "$MOVE_COMMAND" "$BACKUP_PATH" "$INSTALLED_PATH" || fail "unable to restore preserved installation backup"
    validate_app "$INSTALLED_PATH" '' '' || fail "restored installation failed validation"
    register_app "$INSTALLED_PATH" || fail "restored installation failed Launch Services registration"
fi
if path_exists "$STAGE_PATH"; then
    "$REMOVE_COMMAND" -rf "$STAGE_PATH" || fail "unable to remove stale installation staging data"
fi
if path_exists "$INSTALLED_PATH" && [ -L "$INSTALLED_PATH" ]; then
    fail "existing installation must not be a symbolic link"
fi

printf 'Staging Unicorn on the destination filesystem...\n'
"$COPY_COMMAND" "$APP_PATH" "$STAGE_PATH" || fail "unable to stage the candidate app"
validate_app "$STAGE_PATH" "$EXPECTED_VERSION" "$EXPECTED_BUILD" || fail "staged candidate validation failed"
staged_sum=$(/usr/bin/shasum -a 256 "$STAGE_PATH/Contents/MacOS/unicorn" | /usr/bin/awk '{print $1}')
[ "$staged_sum" = "$EXPECTED_EXECUTABLE_SUM" ] || fail "staged executable digest changed"

if path_exists "$INSTALLED_PATH"; then
    validate_app "$INSTALLED_PATH" '' '' || fail "existing Unicorn installation is invalid; refusing to replace it automatically"
    "$MOVE_COMMAND" "$INSTALLED_PATH" "$BACKUP_PATH" || fail "unable to preserve the existing installation"
    BACKUP_CREATED=1
    REPLACEMENT_ACTIVE=1
    snapshot_old_processes "$BACKUP_PATH/Contents/MacOS/unicorn"
fi
REPLACEMENT_ACTIVE=1
"$MOVE_COMMAND" "$STAGE_PATH" "$INSTALLED_PATH" || fail "unable to move the staged app into place"

validate_app "$INSTALLED_PATH" "$EXPECTED_VERSION" "$EXPECTED_BUILD" || fail "installed app failed validation"
installed_sum=$(/usr/bin/shasum -a 256 "$INSTALLED_PATH/Contents/MacOS/unicorn" | /usr/bin/awk '{print $1}')
[ "$installed_sum" = "$EXPECTED_EXECUTABLE_SUM" ] || fail "installed executable digest changed"
if "$XATTR_COMMAND" -r "$INSTALLED_PATH" 2>/dev/null | /usr/bin/grep -Fq com.apple.quarantine; then
    fail "installed app still has the quarantine attribute"
fi
printf 'Registering Unicorn with Launch Services...\n'
register_app "$INSTALLED_PATH" || fail "Launch Services registration or its postcondition failed"

if [ "$BACKUP_CREATED" -eq 1 ]; then
    terminate_old_processes "$BACKUP_PATH/Contents/MacOS/unicorn"
fi

INSTALL_COMMITTED=1
if [ "$BACKUP_CREATED" -eq 1 ]; then
    "$REMOVE_COMMAND" -rf "$BACKUP_PATH" || fail "installation succeeded but backup cleanup failed: $BACKUP_PATH"
    BACKUP_CREATED=0
fi
path_exists "$STAGE_PATH" && fail "installation staging path still exists"
path_exists "$BACKUP_PATH" && fail "installation backup path still exists"
"$REMOVE_COMMAND" -rf "$LOCK_PATH" || fail "installation succeeded but lock cleanup failed: $LOCK_PATH"
LOCK_HELD=0
path_exists "$LOCK_PATH" && fail "installation lock path still exists"

printf '\nSuccess: Unicorn %s (build %s) was installed and registered at %s\n' \
    "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$INSTALLED_PATH"
printf '%s\n' 'Enable it in System Settings > Keyboard > Input Sources > Edit.'
printf '%s\n' '--------------------------------------------------'
