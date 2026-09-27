#!/usr/bin/env bash
# VS Code / 手动包装：先加载 dev/machine.env 再执行命令。
# 用法: ./scripts/with_project_env.sh ./one_click_ship.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"
exec "$@"
