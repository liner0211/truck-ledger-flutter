#!/usr/bin/env bash
# 与 TheosUIApp/TruckLedger/package_ipa.sh 相同思路：Payload + zip。
# .ipa 仅作容器；非越狱安装需自行签名（TrollStore / 证书等）。
set -euo pipefail

APP_NAME="${APP_NAME:-Runner}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  if [[ "${FLUTTER_CLEAN:-0}" == "1" ]]; then
    echo "[1/4] flutter clean..."
    flutter clean
  fi
  echo "[1/4] flutter build ios --release --no-codesign..."
  flutter build ios --release --no-codesign
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

echo "[3/4] Zip ipa..."
(cd "$OUT_DIR" && zip -qry "${APP_NAME}.ipa" "Payload")

echo "[4/4] 完成"
echo "IPA: $IPA_PATH"
