#!/usr/bin/env bash
# 自动发现 Android 设备（USB 或无线 adb），打印 serial（如 192.168.0.128:5555）。
# Usage:
#   ./scripts/find_android_device.sh
#   ./scripts/find_android_device.sh --verbose
# Optional（dev/machine.env）:
#   ANDROID_IP=192.168.0.128
#   ANDROID_ADB_PORT=5555
#   ANDROID_SERIAL=192.168.0.128:5555
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"

VERBOSE=0
if [[ "${1:-}" == "--verbose" ]]; then
  export DISCOVER_ANDROID_VERBOSE=1
  VERBOSE=1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: 未找到 adb。请安装 Android SDK platform-tools。" >&2
  exit 1
fi

echo "正在发现 Android 设备..."
DETECTED="$(python3 "$ROOT_DIR/scripts/discover_android_adb.py")" || {
  echo "ERROR: 未发现可用 Android 设备。" >&2
  echo "  - USB：连接并允许调试" >&2
  echo "  - 无线：手机开启无线调试，或设置 ANDROID_IP=IP:端口" >&2
  echo "  - 多台设备：在 dev/machine.env 设置 ANDROID_SERIAL" >&2
  exit 1
}

echo "Device found: $DETECTED"
echo "$DETECTED"
