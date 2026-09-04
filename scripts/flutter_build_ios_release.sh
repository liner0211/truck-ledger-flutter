#!/usr/bin/env bash
# 与 package_deb / CI 一致：带自动构建号的 iOS release（无签名）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter 不在 PATH" >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$ROOT/scripts/flutter_build_version_env.sh"
if [[ "${SKIP_AUTO_BUILD_NUMBER:-0}" == "1" ]]; then
  exec flutter build ios --release --no-codesign "$@"
else
  exec flutter build ios --release --no-codesign \
    --build-name="$APP_BUILD_NAME" --build-number="$APP_BUILD_NUMBER" "$@"
fi
