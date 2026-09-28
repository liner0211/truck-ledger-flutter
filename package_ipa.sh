#!/usr/bin/env bash
# 使用 CI 已构建的 Runner.app 打成 .ipa 容器。
# 本机禁止 flutter build：须 SKIP_BUILD=1 或在 GitHub Actions 内运行。
set -euo pipefail

APP_NAME="${APP_NAME:-Runner}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ "${GITHUB_ACTIONS:-}" == "true" && "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[1/4] CI 内 flutter build ios…"
  "$ROOT_DIR/scripts/flutter_build_ios_release.sh"
elif [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "ERROR: 禁止本机编译发布包。请 push 触发 Release Packages；客户端走云端更新。" >&2
  exit 1
fi

APP_SRC="$ROOT_DIR/build/ios/iphoneos/${APP_NAME}.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: 未找到: $APP_SRC" >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/ipa-out"
PAYLOAD_DIR="$OUT_DIR/Payload"
IPA_PATH="$OUT_DIR/${APP_NAME}.ipa"

echo "[2/4] 准备 Payload..."
rm -rf "$OUT_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -a "$APP_SRC" "$PAYLOAD_DIR/"

# 自签重签用：把 Push entitlements 放进 IPA 旁与 App 内，便于 codesign --entitlements
ENTITLEMENTS_SRC="$ROOT_DIR/ios/Runner/Runner.entitlements"
if [[ -f "$ENTITLEMENTS_SRC" ]]; then
  cp -f "$ENTITLEMENTS_SRC" "$OUT_DIR/Runner.entitlements"
  cp -f "$ENTITLEMENTS_SRC" "$PAYLOAD_DIR/${APP_NAME}.app/Runner.entitlements"
fi

echo "[3/4] Zip ipa..."
(cd "$OUT_DIR" && zip -qry "${APP_NAME}.ipa" "Payload")

echo "[4/4] 完成"
echo "IPA: $IPA_PATH"
if [[ -f "$OUT_DIR/Runner.entitlements" ]]; then
  echo "Entitlements (自签请带 Push): $OUT_DIR/Runner.entitlements"
fi
