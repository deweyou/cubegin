#!/usr/bin/env bash
set -euo pipefail

require_result() {
  if [[ "$2" != "$3" ]]; then
    echo "$1: expected $3, got $2" >&2
    exit 1
  fi
}

require_result scope "$SCOPE_RESULT" success
require_result apple_build "$APPLE_BUILD_RESULT" success
require_result ios "$IOS_RESULT" success

case "$CHECKS" in
  full) expected=success ;;
  ios) expected=skipped ;;
  *) echo "Unknown CI scope: $CHECKS" >&2; exit 1 ;;
esac

require_result rust "$RUST_RESULT" "$expected"
require_result web "$WEB_RESULT" "$expected"
require_result android "$ANDROID_RESULT" "$expected"
require_result rust_packages "$RUST_PACKAGES_RESULT" "$expected"
require_result web_e2e "$WEB_E2E_RESULT" "$expected"
require_result apple_package "$APPLE_PACKAGE_RESULT" "$expected"
