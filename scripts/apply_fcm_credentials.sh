#!/usr/bin/env bash
# 将 dev/fcm/ 下的 Firebase 凭证装到本机客户端 + 远端服务器（及可选 GitHub Secret）。
# 用法：先按 server-php/FCM_SETUP.md 下载 3 个文件到 dev/fcm/，再执行本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"

FCM_DIR="${FCM_DIR:-$ROOT/dev/fcm}"
SA_SRC="$FCM_DIR/fcm-service-account.json"
GS_SRC="$FCM_DIR/google-services.json"
PLIST_SRC="$FCM_DIR/GoogleService-Info.plist"

SERVER_HOST="${SERVER_HOST:?请在 machine.env 配置 SERVER_HOST}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PATH="${SERVER_PATH:?请在 machine.env 配置 SERVER_PATH}"
SERVER_PORT="${SERVER_PORT:-22}"
SSH_KEY="${SERVER_SSH_KEY:-}"

SSH=(ssh -o StrictHostKeyChecking=accept-new -p "$SERVER_PORT")
SCP=(scp -o StrictHostKeyChecking=accept-new -P "$SERVER_PORT")
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH+=(-i "$SSH_KEY")
  SCP+=(-i "$SSH_KEY")
fi

die() { echo "ERROR: $*" >&2; exit 1; }

echo "==> 检查 $FCM_DIR"
[[ -d "$FCM_DIR" ]] || die "请先：mkdir -p \"$FCM_DIR\" 并放入凭证"
[[ -f "$SA_SRC" ]] || die "缺少 $SA_SRC"
[[ -f "$GS_SRC" ]] || die "缺少 $GS_SRC"

python3 - "$SA_SRC" <<'PY'
import json, sys
j = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("client_email", "private_key", "project_id"):
    if not j.get(k):
        sys.stderr.write(f"服务账号 JSON 缺少 {k}\n")
        sys.exit(1)
print(f"project_id={j['project_id']} email={j['client_email']}")
PY

echo "==> 本机客户端配置"
cp -f "$GS_SRC" "$ROOT/android/app/google-services.json"
chmod 600 "$ROOT/android/app/google-services.json"
echo "    android/app/google-services.json"
if [[ -f "$PLIST_SRC" ]]; then
  cp -f "$PLIST_SRC" "$ROOT/ios/Runner/GoogleService-Info.plist"
  chmod 600 "$ROOT/ios/Runner/GoogleService-Info.plist"
  echo "    ios/Runner/GoogleService-Info.plist"
else
  echo "    （无 iOS plist，跳过）"
fi

echo "==> 上传服务账号到 ${SERVER_HOST}:${SERVER_PATH}/data/"
"${SSH[@]}" "${SERVER_USER}@${SERVER_HOST}" "mkdir -p '$SERVER_PATH/data' && chmod 700 '$SERVER_PATH/data'"
"${SCP[@]}" "$SA_SRC" "${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/data/fcm-service-account.json"
"${SSH[@]}" "${SERVER_USER}@${SERVER_HOST}" \
  "chown www:www '$SERVER_PATH/data/fcm-service-account.json' 2>/dev/null || chown www-data:www-data '$SERVER_PATH/data/fcm-service-account.json' 2>/dev/null || true; chmod 640 '$SERVER_PATH/data/fcm-service-account.json'"

echo "==> 补齐远端 config.php"
"${SSH[@]}" "${SERVER_USER}@${SERVER_HOST}" "python3 - '$SERVER_PATH/config.php'" <<'PY'
import re, sys, shutil, time
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
shutil.copy2(path, f"{path}.bak.{int(time.time())}")
line = "'fcm_service_account_file' => 'data/fcm-service-account.json'"
proj = "'fcm_project_id' => ''"
if "fcm_service_account_file" in src:
    src = re.sub(
        r"['\"]fcm_service_account_file['\"]\s*=>\s*['\"][^'\"]*['\"]",
        line,
        src,
        count=1,
    )
else:
    m = re.search(r"return\s+(?:array\s*)?[\[(]", src)
    if not m:
        raise SystemExit("config 找不到 return [ 或 return array (")
    src = src[: m.end()] + f"\n    {line},\n    {proj},\n" + src[m.end() :]
open(path, "w", encoding="utf-8").write(src)
print("patched", path)
PY

"${SSH[@]}" "${SERVER_USER}@${SERVER_HOST}" \
  "php -r '\$c=require \"$SERVER_PATH/config.php\"; echo \"fcm_file=\".(\$c[\"fcm_service_account_file\"]??\"\").PHP_EOL;'"

echo "==> GitHub Secret GOOGLE_SERVICES_JSON_BASE64"
if command -v gh >/dev/null 2>&1 && [[ "${SKIP_GH_SECRET:-0}" != "1" ]]; then
  REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
  if [[ -n "${REPO:-}" ]]; then
    B64="$(base64 -w0 "$GS_SRC" 2>/dev/null || base64 "$GS_SRC" | tr -d '\n')"
    printf '%s' "$B64" | gh secret set GOOGLE_SERVICES_JSON_BASE64 --repo "$REPO" \
      && echo "    已写入 $REPO" \
      || echo "    写入失败（可稍后手动设 Secret）"
  else
    echo "    无法解析仓库，跳过"
  fi
else
  echo "    跳过"
fi

HEALTH="${SERVER_HEALTH_URL:-https://${SERVER_HOST}/api/health}"
echo "==> 健康检查"
curl -fsS "${HEALTH}?deep=1" | head -c 900 || true
echo
echo
echo "完成。请重装/云端更新司机端（需含 google-services），登录授权通知后杀进程验证。"
echo "文档：server-php/FCM_SETUP.md"
