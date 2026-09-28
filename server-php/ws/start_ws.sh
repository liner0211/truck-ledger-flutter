#!/usr/bin/env bash
# 从站点根目录的 config.php 读取密钥并启动 WebSocket 枢纽。
# 用法（在服务器上）：
#   cd /www/wwwroot/truck.liner0211.online && bash ws/start_ws.sh
# 推荐首次：bash ws/setup_baota_ws.sh（装 Node + Nginx /ws + systemd）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ws"

bash "$ROOT/ws/export_env.sh"
# shellcheck disable=SC1091
set -a
source "$ROOT/data/ws.env"
set +a

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: 未找到 node，请先运行 bash ws/setup_baota_ws.sh" >&2
  exit 1
fi

if [[ ! -d node_modules/ws ]]; then
  echo "==> npm install"
  npm install --omit=dev
fi

# systemd 已托管则交给它
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files truck-ledger-ws.service >/dev/null 2>&1; then
  if systemctl is-enabled --quiet truck-ledger-ws 2>/dev/null || systemctl is-active --quiet truck-ledger-ws 2>/dev/null; then
    echo "==> 通过 systemd 重启 truck-ledger-ws"
    systemctl restart truck-ledger-ws
    sleep 0.5
    curl -fsS "http://127.0.0.1:${WS_PORT}/health" || true
    echo
    exit 0
  fi
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
echo "==> 启动 WS :${WS_PORT} (node=$(command -v node))"
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
