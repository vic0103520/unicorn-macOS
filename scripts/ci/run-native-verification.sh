#!/usr/bin/env bash

set -euo pipefail

XCODEBUILD=${XCODEBUILD:-xcodebuild}

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
    make coverage VERBOSE=1 NO_COLOR=1 \
      2>&1 | tee build/Diagnostics/native-tests-and-coverage.log
    xcrun xccov view --report --only-targets \
      build/Test/Results/UnicornCoreTests.xcresult \
      | tee build/Test/Results/coverage.txt
    ;;
  address-undefined)
    root="$PWD/build/Sanitizers/AddressUndefined"
    rm -rf "$root"
    mkdir -p "$root"
    make test-native \
      XCODEBUILD="$XCODEBUILD -enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES" \
      TEST_ROOT="$root" \
      TEST_RESULT_BUNDLE="$root/UnicornCoreTests.xcresult" \
      NATIVE_ARCH="$(uname -m)" \
      VERBOSE=1 \
      NO_COLOR=1 \
      2>&1 | tee build/Diagnostics/address-undefined-sanitizers.log
    ;;
  thread)
    root="$PWD/build/Sanitizers/Thread"
    rm -rf "$root"
    mkdir -p "$root"
    make test-native \
      XCODEBUILD="$XCODEBUILD -enableThreadSanitizer YES" \
      TEST_ROOT="$root" \
      TEST_RESULT_BUNDLE="$root/UnicornCoreTests.xcresult" \
      NATIVE_ARCH="$(uname -m)" \
      VERBOSE=1 \
      NO_COLOR=1 \
      2>&1 | tee build/Diagnostics/thread-sanitizer.log
    ;;
  *)
    printf 'Unknown native verification mode: %s\n' "$mode" >&2
    usage
    exit 64
    ;;
esac
