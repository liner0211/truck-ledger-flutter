#!/usr/bin/env bash
# 一键：本机 flutter build apk（Release）→ adb install -r 到已连接设备
# 依赖: dev/machine.env 中 FLUTTER_BIN_PATH（或 PATH 已有 flutter）、adb、已开启 USB 调试或已 adb connect
# 多设备时在 machine.env 设置 ANDROID_SERIAL=序列号
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

mapfile -t _devs < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
count="${#_devs[@]}"

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  echo "[一键 Android] 使用 ANDROID_SERIAL=$ANDROID_SERIAL"
  adb -s "$ANDROID_SERIAL" install -r "$APK"
elif [[ "$count" -eq 0 ]]; then
  echo "ERROR: 没有已连接且授权的设备。请 USB 连接并允许调试，或执行: adb connect IP:5555" >&2
  exit 1
elif [[ "$count" -gt 1 ]]; then
  echo "ERROR: 检测到多台设备: ${_devs[*]}" >&2
  echo "请在 dev/machine.env 设置 ANDROID_SERIAL=其中一台的序列号，或只保留一台连接。" >&2
  exit 1
else
  echo "[一键 Android] 正在安装到设备 ${_devs[0]} ..."
  adb install -r "$APK"
fi
echo "[一键 Android] 完成: $APK"
