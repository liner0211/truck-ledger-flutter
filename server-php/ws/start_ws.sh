#!/usr/bin/env bash
# 从站点根目录的 config.php 读取密钥并启动 WebSocket 枢纽。
# 用法（在服务器上）：
#   cd /www/wwwroot/truck.liner0211.online && bash ws/start_ws.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ws"

if [[ ! -f "$ROOT/config.php" ]]; then
  echo "ERROR: 缺少 $ROOT/config.php" >&2
  exit 1
fi

eval "$(
  php -r '
    $c = require "'"$ROOT"'/config.php";
    $secret = (string)($c["jwt_secret"] ?? "");
    $internal = (string)($c["ws_internal_token"] ?? "");
    if ($internal === "") {
      $internal = hash("sha256", $secret . "|ws-internal");
    }
    $port = (int)($c["ws_port"] ?? 8765);
    echo "export JWT_SECRET=" . escapeshellarg($secret) . "\n";
    echo "export WS_INTERNAL_TOKEN=" . escapeshellarg($internal) . "\n";
    echo "export WS_PORT=" . escapeshellarg((string)$port) . "\n";
  '
)"

if [[ ! -d node_modules/ws ]]; then
  echo "==> npm install"
  npm install --omit=dev
fi

# 若已在跑则先停
if [[ -f "$ROOT/data/ws.pid" ]]; then
  old="$(cat "$ROOT/data/ws.pid" 2>/dev/null || true)"
  if [[ -n "${old:-}" ]] && kill -0 "$old" 2>/dev/null; then
    echo "==> 停止旧进程 pid=$old"
    kill "$old" || true
    sleep 1
  fi
fi

mkdir -p "$ROOT/data"
echo "==> 启动 WS :${WS_PORT}"
nohup node server.js >>"$ROOT/data/ws.log" 2>&1 &
echo $! >"$ROOT/data/ws.pid"
sleep 0.5
if kill -0 "$(cat "$ROOT/data/ws.pid")" 2>/dev/null; then
  echo "OK pid=$(cat "$ROOT/data/ws.pid") log=$ROOT/data/ws.log"
  curl -fsS "http://127.0.0.1:${WS_PORT}/health" || true
  echo
else
  echo "ERROR: 启动失败，见 $ROOT/data/ws.log" >&2
  exit 1
fi
