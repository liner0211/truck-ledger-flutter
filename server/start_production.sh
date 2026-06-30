#!/usr/bin/env bash
# 生产环境启动（无 reload，供 Supervisor / 宝塔 Python 项目使用）
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
WORKERS="${WORKERS:-2}"

VENV_PYTHON="./venv/bin/python"
if [[ ! -x "$VENV_PYTHON" ]]; then
  VENV_PYTHON="python3"
fi

exec "$VENV_PYTHON" -m uvicorn main:app \
  --host "$HOST" \
  --port "$PORT" \
  --workers "$WORKERS"
