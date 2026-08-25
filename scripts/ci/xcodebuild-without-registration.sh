#!/usr/bin/env bash

set -euo pipefail

# Xcode unconditionally invokes lsregister for macOS app products. Denying that
# subprocess file access makes registration fail safely without affecting the build.
lsregister_process_pattern='.*/Support/lsregister$'
profile="(version 1)
(allow default)
(deny file-read*
  (process-path-regex #\"${lsregister_process_pattern}\"))"

exec sandbox-exec -p "$profile" xcodebuild "$@"
