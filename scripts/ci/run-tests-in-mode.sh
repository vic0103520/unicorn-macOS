#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s {coverage|address-undefined}\n' "$0" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

mode="$1"
mkdir -p build/Diagnostics

case "$mode" in
  coverage)
    make --silent _test-native \
      2>&1 | tee build/Diagnostics/tests-and-coverage.log
    if ! xcrun xccov view --report --only-targets \
      build/Test/Results/UnicornCoreTests.xcresult \
      | tee build/Test/Results/coverage.txt; then
      printf 'Coverage rendering failed; test results remain authoritative.\n' >&2
    fi
    ;;
  address-undefined)
    root="$PWD/build/Sanitizers/AddressUndefined"
    rm -rf "$root"
    mkdir -p "$root"
    make --silent _test-native \
      XCODEBUILD='xcodebuild -enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES' \
      TEST_ROOT="$root" \
      TEST_RESULT_BUNDLE="$root/UnicornCoreTests.xcresult" \
      NATIVE_ARCH="$(uname -m)" \
      2>&1 | tee build/Diagnostics/address-undefined-sanitizers.log
    ;;
  *)
    printf 'Unknown test mode: %s\n' "$mode" >&2
    usage
    exit 64
    ;;
esac
