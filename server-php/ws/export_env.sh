#!/usr/bin/env bash
# 从站点 config.php 导出 WS 环境变量到 data/ws.env
# 格式兼容 systemd EnvironmentFile（无 shell 引号）与 `set -a; source`
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/data"
OUT="$ROOT/data/ws.env"

if [[ ! -f "$ROOT/config.php" ]]; then
  echo "ERROR: 缺少 $ROOT/config.php" >&2
  exit 1
fi

php -r '
  $c = require "'"$ROOT"'/config.php";
  $secret = (string)($c["jwt_secret"] ?? "");
  $internal = (string)($c["ws_internal_token"] ?? "");
  if ($internal === "") {
    $internal = hash("sha256", $secret . "|ws-internal");
  }
  $port = (int)($c["ws_port"] ?? 8765);
  // systemd EnvironmentFile：避免换行；特殊字符尽量不用引号包裹的复杂值
  $esc = static function (string $v): string {
    return str_replace(["\n", "\r", "\\"], ["", "", "\\\\"], $v);
  };
  $body = "JWT_SECRET=" . $esc($secret) . "\n"
    . "WS_INTERNAL_TOKEN=" . $esc($internal) . "\n"
    . "WS_PORT=" . $port . "\n";
  if (file_put_contents("'"$OUT"'", $body) === false) {
    fwrite(STDERR, "write failed\n");
    exit(1);
  }
'

chmod 600 "$OUT" 2>/dev/null || true
echo "OK wrote $OUT"
