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
flutter build apk "$@"
