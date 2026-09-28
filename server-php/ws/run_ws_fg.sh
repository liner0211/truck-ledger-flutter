#!/usr/bin/env bash
# 前台运行 WS（供 systemd ExecStart）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ws"
bash "$ROOT/ws/export_env.sh"
# shellcheck disable=SC1091
set -a
source "$ROOT/data/ws.env"
set +a
exec node server.js
