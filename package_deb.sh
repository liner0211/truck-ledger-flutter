#!/usr/bin/env bash
# 使用 flutter 构建的 Runner.app 组装 Cydia 风格 deb（安装到 /Applications）。
# 需在 macOS 上执行（flutter build ios 依赖 Xcode）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Runner}"
APP_SRC="$ROOT_DIR/build/ios/iphoneos/${APP_NAME}.app"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter 不在 PATH 中" >&2
  exit 1
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  if [[ "${FLUTTER_CLEAN:-0}" == "1" ]]; then
    echo "[package_deb] flutter clean..."
    flutter clean
  fi
  echo "[package_deb] flutter build ios --release --no-codesign..."
  flutter build ios --release --no-codesign
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: 未找到构建产物: $APP_SRC" >&2
  exit 1
fi

VERSION_DEB="$(
  python3 - <<'PY'
import re
from pathlib import Path

text = Path("pubspec.yaml").read_text(encoding="utf-8")
m = re.search(r"(?m)^version:\s*([^\s#]+)", text)
if not m:
    raise SystemExit("cannot parse version from pubspec.yaml")
raw = m.group(1).strip().strip("'\"")
if "+" in raw:
    a, b = raw.split("+", 1)
    print(f"{a}-{b}")
else:
    print(raw)
PY
)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/truckledger-deb.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/DEBIAN" "$STAGE/Applications"
cp "$ROOT_DIR/control" "$STAGE/DEBIAN/control"
if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' "s/^Version: .*/Version: ${VERSION_DEB}/" "$STAGE/DEBIAN/control"
else
  sed -i "s/^Version: .*/Version: ${VERSION_DEB}/" "$STAGE/DEBIAN/control"
fi

echo "[package_deb] 复制 ${APP_NAME}.app -> staging/Applications/ ..."
cp -a "$APP_SRC" "$STAGE/Applications/"

mkdir -p "$ROOT_DIR/packages"
DEB_NAME="com.liner0211.truckledger_${VERSION_DEB}_iphoneos-arm64e.deb"
DEB_PATH="$ROOT_DIR/packages/$DEB_NAME"

if command -v fakeroot >/dev/null 2>&1; then
  echo "[package_deb] dpkg-deb (fakeroot)..."
  fakeroot dpkg-deb -Zxz -b "$STAGE" "$DEB_PATH"
else
  echo "[package_deb] dpkg-deb（无 fakeroot，属主为当前用户）..."
  dpkg-deb -Zxz -b "$STAGE" "$DEB_PATH"
fi

echo "DEB: $DEB_PATH"
