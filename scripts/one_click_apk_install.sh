#!/usr/bin/env bash
# 一键：本机 flutter build apk（Release）→ adb install -r 到已连接设备
# 依赖: dev/machine.env 中 FLUTTER_BIN_PATH（或 PATH 已有 flutter）、adb
# 自动发现：USB 已连接设备，或扫描局域网无线 adb（默认端口 5555，见 discover_android_adb.py）
# 多设备时在 machine.env 设置 ANDROID_SERIAL=序列号；固定 IP 可设 ANDROID_IP
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: 未找到 adb。请安装 Android SDK platform-tools 并加入 PATH。" >&2
  exit 1
fi

echo "[一键 Android] 正在编译 Release APK..."
"$ROOT_DIR/scripts/build_apk.sh" --release

APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK" ]]; then
  echo "ERROR: 未找到产物: $APK" >&2
  exit 1
fi

echo "[一键 Android] 正在发现设备..."
ANDROID_TARGET="$(
  python3 "$ROOT_DIR/scripts/discover_android_adb.py"
)" || {
  echo "ERROR: 未发现可用 Android 设备。" >&2
  echo "  USB：连接并允许调试；无线：开启无线调试（默认端口 5555）" >&2
  echo "  或设置 ANDROID_IP=192.168.x.x；多台设备设置 ANDROID_SERIAL" >&2
  exit 1
}
echo "[一键 Android] Device found: $ANDROID_TARGET"
echo "[一键 Android] 正在安装..."
adb -s "$ANDROID_TARGET" install -r "$APK"
echo "[一键 Android] 完成: $APK"
