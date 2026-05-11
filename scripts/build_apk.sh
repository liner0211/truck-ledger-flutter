#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${FLUTTER_BIN_PATH:-/home/liner0211/Code/.flutter_toolchain/flutter/bin}:$PATH"
cd "$ROOT"
flutter pub get
flutter build apk "$@"
