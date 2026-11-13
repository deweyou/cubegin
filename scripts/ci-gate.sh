#!/usr/bin/env bash
set -euo pipefail

require_result() {
  if [[ "$2" != "$3" ]]; then
    echo "$1: expected $3, got $2" >&2
    exit 1
  fi
}

require_result scope "$SCOPE_RESULT" success

core=skipped
web=skipped
apple=skipped
docs=skipped

case "$CHECKS" in
  full) core=success; web=success; apple=success ;;
  ios) apple=success ;;
  docs) docs=success ;;
  docs-web) docs=success; web=success ;;
  *) echo "Unknown CI scope: $CHECKS" >&2; exit 1 ;;
esac

require_result docs "$DOCS_RESULT" "$docs"
require_result apple_build "$APPLE_BUILD_RESULT" "$apple"
require_result ios "$IOS_RESULT" "$apple"
require_result rust "$RUST_RESULT" "$core"
require_result web "$WEB_RESULT" "$web"
require_result android "$ANDROID_RESULT" "$core"
require_result rust_packages "$RUST_PACKAGES_RESULT" "$core"
require_result web_e2e "$WEB_E2E_RESULT" "$core"
require_result apple_package "$APPLE_PACKAGE_RESULT" "$core"
