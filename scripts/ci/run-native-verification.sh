#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s {coverage|address-undefined|thread}\n' "$0" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

mode="$1"
mkdir -p build/Diagnostics

case "$mode" in
  coverage)
    # The coverage target also cross-compiles the app. Xcode's automatic build-product
    # registration is contained by ephemeral runner teardown; CI never installs or activates it.
    make --silent coverage \
      2>&1 | tee build/Diagnostics/native-tests-and-coverage.log
    xcrun xccov view --report --only-targets \
      build/Test/Results/UnicornCoreTests.xcresult \
      | tee build/Test/Results/coverage.txt
    ;;
  address-undefined)
    root="$PWD/build/Sanitizers/AddressUndefined"
    rm -rf "$root"
    mkdir -p "$root"
    make --silent test-native \
      XCODEBUILD='xcodebuild -enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES' \
      TEST_ROOT="$root" \
      TEST_RESULT_BUNDLE="$root/UnicornCoreTests.xcresult" \
      NATIVE_ARCH="$(uname -m)" \
      2>&1 | tee build/Diagnostics/address-undefined-sanitizers.log
    ;;
  thread)
    root="$PWD/build/Sanitizers/Thread"
    rm -rf "$root"
    mkdir -p "$root"
    make --silent test-native \
      XCODEBUILD='xcodebuild -enableThreadSanitizer YES' \
      TEST_ROOT="$root" \
      TEST_RESULT_BUNDLE="$root/UnicornCoreTests.xcresult" \
      NATIVE_ARCH="$(uname -m)" \
      2>&1 | tee build/Diagnostics/thread-sanitizer.log
    ;;
  *)
    printf 'Unknown native verification mode: %s\n' "$mode" >&2
    usage
    exit 64
    ;;
esac
