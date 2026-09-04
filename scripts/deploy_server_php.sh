#!/usr/bin/env bash
# 将 server-php/ 同步到生产机（保留远端 config.php 与 data/）。
# 依赖：rsync、ssh；配置见 dev/machine.env（SERVER_*）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/project_env.sh"

SERVER_HOST="${SERVER_HOST:-}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PORT="${SERVER_PORT:-22}"
SERVER_PATH="${SERVER_PATH:-/www/wwwroot/truck.liner0211.online}"
SERVER_SSH_KEY="${SERVER_SSH_KEY:-}"

if [[ -z "$SERVER_HOST" ]]; then
  echo "错误：请在 dev/machine.env 设置 SERVER_HOST（服务器 IP 或域名）" >&2
  exit 1
fi

SRC="$ROOT/server-php/"
DEST="${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/"

SSH_OPTS=(-p "$SERVER_PORT" -o StrictHostKeyChecking=accept-new)
if [[ -n "$SERVER_SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SERVER_SSH_KEY")
fi

RSYNC_SSH="ssh ${SSH_OPTS[*]}"

echo "==> 同步 server-php → $DEST"
echo "    （跳过远端 config.php、data/）"

rsync -avz --delete \
  --exclude 'config.php' \
  --exclude 'data/' \
  --exclude '.git/' \
  --exclude '*.zip' \
  --exclude '.user.ini' \
  --exclude '.well-known/' \
  --exclude 'public/.well-known/' \
  -e "$RSYNC_SSH" \
  "$SRC" "$DEST"

echo "==> 远端权限与自检"
ssh "${SSH_OPTS[@]}" "${SERVER_USER}@${SERVER_HOST}" bash -s <<EOF
set -e
cd '$SERVER_PATH'
mkdir -p data/attachments
# 宝塔常见运行用户 www
if id www >/dev/null 2>&1; then
  chown -R www:www data 2>/dev/null || true
  chmod -R 755 data 2>/dev/null || true
fi
if [[ ! -f config.php ]]; then
  echo '警告：远端尚无 config.php，请从 config.example.php 复制并填写密钥'
fi
# 语法检查（若有 php）
if command -v php >/dev/null 2>&1; then
  php -l public/index.php >/dev/null && echo 'PHP 语法 OK'
fi
EOF

echo "==> 健康检查"
HEALTH_URL="${SERVER_HEALTH_URL:-https://${SERVER_HOST}/api/health?deep=1}"
# 若 HOST 是 IP，用户应设置 SERVER_HEALTH_URL
if [[ "$SERVER_HOST" =~ ^[0-9.]+$ ]] && [[ -z "${SERVER_HEALTH_URL:-}" ]]; then
  echo "跳过 HTTPS 健康检查（SERVER_HOST 为 IP，请设 SERVER_HEALTH_URL）"
else
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 20 "$HEALTH_URL" | head -c 500 || echo "健康检查请求失败（请确认域名/SSL）"
    echo
  fi
fi

echo "完成。管理后台：https://你的域名/admin"
