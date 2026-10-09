#!/bin/sh

# shellcheck disable=SC2034 # Used by scripts that source this test library.
TEST_ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_PASS_COUNT=0

pass() {
    TEST_PASS_COUNT=$((TEST_PASS_COUNT + 1))
    printf '[PASS] %s\n' "$1"
}

fail_test() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail_test "expected file: $1"
}

assert_not_exists() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        fail_test "unexpected path: $1"
    fi
}

assert_contains() {
    /usr/bin/grep -Fq "$2" "$1" || fail_test "expected '$2' in $1"
}

assert_not_contains() {
    if /usr/bin/grep -Fq "$2" "$1"; then
        fail_test "did not expect '$2' in $1"
    fi
}

plist_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$2"
}

create_test_app() {
    test_app_path=$1
    test_app_version=$2
    test_app_build=$3
    test_app_marker=$4

    /bin/mkdir -p "$test_app_path/Contents/MacOS" "$test_app_path/Contents/Resources"
    cat > "$test_app_path/Contents/Info.plist" <<EOF
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
    <string>$test_app_version</string>
    <key>CFBundleVersion</key>
    <string>$test_app_build</string>
</dict>
</plist>
EOF
    cat > "$test_app_path/Contents/MacOS/source.c" <<EOF
#include <stdio.h>
int main(void) { puts("$test_app_marker"); return 0; }
EOF
    /usr/bin/clang "$test_app_path/Contents/MacOS/source.c" -o "$test_app_path/Contents/MacOS/unicorn"
    /bin/rm "$test_app_path/Contents/MacOS/source.c"
    printf '{}\n' > "$test_app_path/Contents/Resources/keymap.json"
    /usr/bin/codesign --force --sign - "$test_app_path" >/dev/null 2>&1
}

copy_release_assets() {
    /bin/mkdir -p "$2"
    /bin/cp "$1/unicorn-macos.zip" "$1/SHA256SUMS" "$1/UNICORN_EXECUTABLE_SHA256" "$2/"
}

expect_failure() {
    test_failure_name=$1
    shift
    test_failure_output=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unicorn-expected-failure.XXXXXX")
    if "$@" > "$test_failure_output" 2>&1; then
        /bin/cat "$test_failure_output" >&2
        /bin/rm -f "$test_failure_output"
        fail_test "$test_failure_name unexpectedly succeeded"
    fi
    if /usr/bin/grep -Eq '(^| )Success(:|!)|verification succeeded' "$test_failure_output"; then
        /bin/cat "$test_failure_output" >&2
        /bin/rm -f "$test_failure_output"
        fail_test "$test_failure_name printed success"
    fi
    /bin/rm -f "$test_failure_output"
    pass "$test_failure_name"
}

write_archive_sum() {
    test_assets=$1
    test_sum=$(/usr/bin/shasum -a 256 "$test_assets/unicorn-macos.zip" | /usr/bin/awk '{print $1}')
    printf '%s  unicorn-macos.zip\n' "$test_sum" > "$test_assets/SHA256SUMS"
}

rebuild_test_archive() {
    test_payload=$1
    test_assets=$2
    /bin/rm -f "$test_assets/unicorn-macos.zip"
    (
        cd "$test_payload" || exit 1
        COPYFILE_DISABLE=1 LC_ALL=C /usr/bin/find . -mindepth 1 -print |
            /usr/bin/sed 's|^\./||' |
            LC_ALL=C /usr/bin/sort |
            /usr/bin/zip -X -q -y "$test_assets/unicorn-macos.zip" -@
    )
    write_archive_sum "$test_assets"
}

make_fake_launch_services() {
    test_fake_path=$1
    cat > "$test_fake_path" <<'EOF'
#!/bin/sh
set -eu
DB=${UNICORN_TEST_LS_DB:?}
case ${1:-} in
    -f)
        app_path=$2
        version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")
        if [ "${UNICORN_TEST_LS_FAIL_VERSION:-}" = "$version" ]; then
            exit 41
        fi
        printf '%s\n' "$app_path" > "$DB"
        ;;
    -dump)
        if [ "${UNICORN_TEST_LS_OMIT_POSTCONDITION:-0}" = 1 ]; then
            exit 0
        fi
        if [ -f "$DB" ]; then
            while IFS= read -r app_path; do
                version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")
                if [ "${UNICORN_TEST_LS_OMIT_VERSION:-}" != "$version" ]; then
                    printf 'path:                       %s (0x1234)\n' "$app_path"
                fi
            done < "$DB"
        fi
        ;;
    *) exit 2 ;;
esac
EOF
    /bin/chmod 755 "$test_fake_path"
}
