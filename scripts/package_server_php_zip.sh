#!/usr/bin/env bash
# 打包 server-php 为可上传宝塔的 zip（排除 config.php、data、.git）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/server-php-release.zip}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/server-php"
rsync -a \
  --exclude 'config.php' \
  --exclude 'data/' \
  --exclude '.git/' \
  --exclude '*.zip' \
  "$ROOT/server-php/" "$TMP/server-php/"

(
  cd "$TMP"
  rm -f "$OUT"
  zip -qr "$OUT" server-php
)

echo "已生成: $OUT"
ls -lh "$OUT"
