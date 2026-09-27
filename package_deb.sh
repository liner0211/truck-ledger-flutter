#!/usr/bin/env bash
# 使用 CI 已构建的 Runner.app 组装 Cydia 风格 deb（安装到 /Applications）。
# 本机禁止 flutter build：必须 SKIP_BUILD=1，且存在 build/ios/iphoneos/Runner.app（由 CI 产物解压）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Runner}"
APP_SRC="$ROOT_DIR/build/ios/iphoneos/${APP_NAME}.app"

if [[ "${GITHUB_ACTIONS:-}" == "true" && "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[package_deb] CI 内构建 Runner.app…"
  "$ROOT_DIR/scripts/flutter_build_ios_release.sh"
elif [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "ERROR: 禁止本机编译发布包。请 push 触发 Release Packages；客户端走云端更新。" >&2
  echo "  （CI 流水线内会自动构建；本地打包请设 SKIP_BUILD=1 并提供 CI 产物 Runner.app）" >&2
  exit 1
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: 未找到构建产物: $APP_SRC" >&2
  echo "  请从 CI 下载 Runner.app.zip 解压，或直接拉取 Release 中的 .deb。" >&2
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

# 安装后修复权限（关键）：部分越狱环境在 resign/appatch 后会把 Frameworks 目录权限改得过严（700），导致秒闪。
cat > "$STAGE/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -e

APP="/Applications/Runner.app"
if [ -d "$APP" ]; then
  # 让 mobile 进程可读取框架与资源
  chmod -R a+rX "$APP" || true
  chmod 755 "$APP" "$APP/Runner" 2>/dev/null || true
fi

exit 0
SH
chmod 755 "$STAGE/DEBIAN/postinst"

echo "[package_deb] 复制 ${APP_NAME}.app -> staging/Applications/ ..."
cp -a "$APP_SRC" "$STAGE/Applications/"
APP_STAGE="$STAGE/Applications/${APP_NAME}.app"

# GitHub artifact 解压后可能带来过严权限（如 700/600），会导致 mobile 进程无法读取 Framework 而闪退。
# 这里统一修正为 iOS App 常见权限：目录 755，普通文件 644，可执行文件 755。
echo "[package_deb] 规范化 ${APP_NAME}.app 权限..."
python3 - "$APP_STAGE" <<'PY'
import os
import stat
import sys

root = sys.argv[1]

for cur, dirs, files in os.walk(root):
    for d in dirs:
        p = os.path.join(cur, d)
        if os.path.islink(p):
            continue
        os.chmod(p, 0o755)
    for f in files:
        p = os.path.join(cur, f)
        if os.path.islink(p):
            continue
        mode = os.stat(p).st_mode
        if mode & stat.S_IXUSR or mode & stat.S_IXGRP or mode & stat.S_IXOTH:
            os.chmod(p, 0o755)
        else:
            os.chmod(p, 0o644)
PY

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
