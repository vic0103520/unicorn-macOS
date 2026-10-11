#!/bin/bash
set -euo pipefail

app_bundle=${1:?usage: verify-release-build.sh APP_BUNDLE}
executable="$app_bundle/Contents/MacOS/unicorn"
info_plist="$app_bundle/Contents/Info.plist"

required_paths=(
  "$executable"
  "$info_plist"
  "$app_bundle/Contents/Resources/keymap.json"
  "$app_bundle/Contents/Resources/Base.lproj/Main.storyboardc/Info.plist"
  "$app_bundle/Contents/Resources/en.lproj/InfoPlist.strings"
)
for path in "${required_paths[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing expected bundle file: $path" >&2
    exit 1
  fi
done

build_settings=$(xcodebuild \
  -project unicorn.xcodeproj \
  -target unicorn \
  -configuration Release \
  -showBuildSettings)

build_setting() {
  local name=$1
  awk -F ' = ' -v name="$name" '$1 == "    " name { print $2; exit }' <<< "$build_settings"
}

assert_plist_matches_setting() {
  local plist_key=$1
  local setting_name=$2
  local actual expected
  actual=$(/usr/libexec/PlistBuddy -c "Print :$plist_key" "$info_plist")
  expected=$(build_setting "$setting_name")
  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "$plist_key mismatch: actual='$actual', $setting_name='$expected'" >&2
    exit 1
  fi
  echo "$plist_key: $actual"
}

assert_plist_matches_setting CFBundleIdentifier PRODUCT_BUNDLE_IDENTIFIER
assert_plist_matches_setting CFBundleShortVersionString MARKETING_VERSION
assert_plist_matches_setting CFBundleVersion CURRENT_PROJECT_VERSION
assert_plist_matches_setting LSMinimumSystemVersion MACOSX_DEPLOYMENT_TARGET

codesign --verify --deep --strict --verbose=2 "$app_bundle"
signing_details=$(codesign -dvvv "$app_bundle" 2>&1)
printf '%s\n' "$signing_details"
grep -q '^Signature=adhoc$' <<< "$signing_details"
grep -q '^TeamIdentifier=not set$' <<< "$signing_details"

echo "Release bundle verification passed. Cross-architecture compilation is not runtime compatibility evidence."
