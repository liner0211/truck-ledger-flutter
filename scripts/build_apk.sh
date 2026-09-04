#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: 未找到 flutter。请在 dev/machine.env 设置 FLUTTER_BIN_PATH=/你的/flutter/bin" >&2
  exit 1
fi
flutter pub get
# shellcheck disable=SC1091
source "$ROOT/scripts/flutter_build_version_env.sh"
if [[ "${SKIP_AUTO_BUILD_NUMBER:-0}" == "1" ]]; then
  flutter build apk "$@"
else
  flutter build apk "$@" --build-name="$APP_BUILD_NAME" --build-number="$APP_BUILD_NUMBER"
fi
