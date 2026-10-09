#!/bin/sh

# shellcheck disable=SC2034 # Constants are consumed by scripts that source this library.
RELEASE_ARCHIVE_NAME="unicorn-macos.zip"
RELEASE_ARCHIVE_SUMS_NAME="SHA256SUMS"
RELEASE_EXECUTABLE_SUM_NAME="UNICORN_EXECUTABLE_SHA256"
RELEASE_METADATA_NAME="release-metadata.json"
RELEASE_NOTES_NAME="RELEASE_NOTES.md"
RELEASE_APP_NAME="unicorn.app"
RELEASE_BUNDLE_IDENTIFIER="Vic-Shih.inputmethod.unicorn"
RELEASE_EXECUTABLE_PATH="unicorn.app/Contents/MacOS/unicorn"

release_error() {
    printf 'Error: %s\n' "$*" >&2
}

release_fail() {
    release_error "$*"
    exit 1
}

release_marketing_version() {
    release_tag=$1
    release_test_suffix=

    case "$release_tag" in
        v*)
            release_version=${release_tag#v}
            ;;
        test-v*)
            release_test_value=${release_tag#test-v}
            release_version=${release_test_value%-*}
            release_test_suffix=${release_test_value##*-}
            case "$release_test_suffix" in
                ''|*[!0-9]*) return 1 ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac

    if ! printf '%s\n' "$release_version" | /usr/bin/grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
        return 1
    fi

    case "$release_tag" in
        "v$release_version"|"test-v$release_version-$release_test_suffix")
            printf '%s\n' "$release_version"
            ;;
        *)
            return 1
            ;;
    esac
}

release_validate_build_number() {
    case $1 in
        ''|0|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

release_plist_value() {
    release_plist_key=$1
    release_plist_path=$2
    /usr/bin/plutil -extract "$release_plist_key" raw -o - "$release_plist_path" 2>/dev/null
}

release_json_value() {
    release_json_key=$1
    release_json_path=$2
    /usr/bin/plutil -extract "$release_json_key" raw -o - "$release_json_path" 2>/dev/null
}

release_sha256() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

release_validate_app() {
    release_app_path=$1
    release_expected_version=$2
    release_expected_build=$3
    release_info_path="$release_app_path/Contents/Info.plist"
    release_executable_path="$release_app_path/Contents/MacOS/unicorn"
    release_keymap_path="$release_app_path/Contents/Resources/keymap.json"

    [ -d "$release_app_path" ] || { release_error "app bundle is missing: $release_app_path"; return 1; }
    [ ! -L "$release_app_path" ] || { release_error "app bundle must not be a symbolic link"; return 1; }
    [ -f "$release_info_path" ] || { release_error "app Info.plist is missing"; return 1; }
    [ -f "$release_executable_path" ] || { release_error "app executable is missing"; return 1; }
    [ -x "$release_executable_path" ] || { release_error "app executable is not executable"; return 1; }
    [ -f "$release_keymap_path" ] || { release_error "required keymap.json is missing"; return 1; }

    release_bundle_identifier=$(release_plist_value CFBundleIdentifier "$release_info_path") || {
        release_error "CFBundleIdentifier is missing"
        return 1
    }
    release_bundle_executable=$(release_plist_value CFBundleExecutable "$release_info_path") || {
        release_error "CFBundleExecutable is missing"
        return 1
    }
    release_bundle_version=$(release_plist_value CFBundleShortVersionString "$release_info_path") || {
        release_error "CFBundleShortVersionString is missing"
        return 1
    }
    release_bundle_build=$(release_plist_value CFBundleVersion "$release_info_path") || {
        release_error "CFBundleVersion is missing"
        return 1
    }

    [ "$release_bundle_identifier" = "$RELEASE_BUNDLE_IDENTIFIER" ] || {
        release_error "unexpected bundle identifier: $release_bundle_identifier"
        return 1
    }
    [ "$release_bundle_executable" = "unicorn" ] || {
        release_error "unexpected bundle executable: $release_bundle_executable"
        return 1
    }
    [ -z "$release_expected_version" ] || [ "$release_bundle_version" = "$release_expected_version" ] || {
        release_error "bundle marketing version $release_bundle_version does not match $release_expected_version"
        return 1
    }
    [ -z "$release_expected_build" ] || [ "$release_bundle_build" = "$release_expected_build" ] || {
        release_error "bundle build number $release_bundle_build does not match $release_expected_build"
        return 1
    }

    release_signature=$(/usr/bin/codesign -dv --verbose=4 "$release_app_path" 2>&1) || {
        release_error "unable to inspect app signature"
        return 1
    }
    printf '%s\n' "$release_signature" | /usr/bin/grep -Fqx 'Signature=adhoc' || {
        release_error "app must use the documented ad-hoc signature policy"
        return 1
    }
    printf '%s\n' "$release_signature" | /usr/bin/grep -Fqx 'TeamIdentifier=not set' || {
        release_error "ad-hoc app must not claim an Apple Team ID"
        return 1
    }
    printf '%s\n' "$release_signature" | /usr/bin/grep -Fqx "Identifier=$RELEASE_BUNDLE_IDENTIFIER" || {
        release_error "code-signing identifier does not match $RELEASE_BUNDLE_IDENTIFIER"
        return 1
    }
    /usr/bin/codesign --verify --deep --strict "$release_app_path" >/dev/null 2>&1 || {
        release_error "app signature verification failed"
        return 1
    }
}

release_write_notes() {
    release_notes_tag=$1
    release_notes_version=$2
    release_notes_build=$3
    release_notes_archive_sum=$4
    release_notes_executable_sum=$5
    release_notes_output=$6

    cat > "$release_notes_output" <<EOF
# Unicorn $release_notes_tag

This archive contains Unicorn $release_notes_version (build $release_notes_build).

## Integrity verification

The SHA-256 value below covers the exact final ZIP archive bytes:

\`\`\`text
$release_notes_archive_sum  $RELEASE_ARCHIVE_NAME
\`\`\`

The separately useful digest for the executable inside that archive is:

\`\`\`text
$release_notes_executable_sum  $RELEASE_EXECUTABLE_PATH
\`\`\`

Download \`$RELEASE_ARCHIVE_NAME\` and \`$RELEASE_ARCHIVE_SUMS_NAME\` into the same directory, then run:

\`\`\`sh
shasum -a 256 -c $RELEASE_ARCHIVE_SUMS_NAME
\`\`\`

SHA-256 detects accidental corruption or a mismatch between these two downloaded files. Because both files are hosted on the same release and Unicorn is ad-hoc signed, this check does not authenticate the publisher or establish Apple developer identity.
EOF
}
