#!/usr/bin/env bash
# 一键发版总控：提交(可选) → push → 等 CI 编译/上传 downloads/更新控制面/部署后端 → 可选装到本机设备。
#
# 用法:
#   ./one_click_ship.sh
#   ./one_click_ship.sh -m "修复某某"
#   ./one_click_ship.sh --install-apk --install-deb
#   SHIP_INSTALL_APK=1 ./one_click_ship.sh
#
# 依赖: git、gh（已 login）、可选 adb / DEVICE_PASS（装包时）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"

COMMIT_MSG="${SHIP_COMMIT_MSG:-}"
DO_WAIT=1
INSTALL_APK="${SHIP_INSTALL_APK:-0}"
INSTALL_DEB="${SHIP_INSTALL_DEB:-0}"
INSTALL_IPA="${SHIP_INSTALL_IPA:-0}"
LOCAL_SERVER="${SHIP_LOCAL_SERVER:-1}"
POLL_SEC="${SHIP_POLL_SEC:-20}"
TIMEOUT_MIN="${SHIP_TIMEOUT_MIN:-90}"

usage() {
  cat <<'EOF'
一键发版：push → 等待 GitHub Actions（编译包、上传 downloads、更新控制面、部署 PHP）→ 可选安装

  ./one_click_ship.sh [选项]

选项:
  -m, --message MSG   有未提交改动时自动 git commit（MSG 为说明）
  --no-wait           只 push，不等 CI
  --no-local-server   有 server-php 变更时也不本机 rsync（只靠 CI Deploy）
  --install-apk       CI 成功后 adb 安装最新 APK
  --install-deb       CI 成功后安装越狱 deb
  --install-ipa       CI 成功后拉取 IPA 到 ipa-out/
  --install-all       上述三种安装都做
  -h, --help          帮助

环境变量（同名覆盖）: SHIP_COMMIT_MSG, SHIP_INSTALL_APK/DEB/IPA=1,
  SHIP_LOCAL_SERVER=0, SHIP_POLL_SEC, SHIP_TIMEOUT_MIN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message) COMMIT_MSG="${2:-}"; shift 2 ;;
    --no-wait) DO_WAIT=0; shift ;;
    --no-local-server) LOCAL_SERVER=0; shift ;;
    --install-apk) INSTALL_APK=1; shift ;;
    --install-deb) INSTALL_DEB=1; shift ;;
    --install-ipa) INSTALL_IPA=1; shift ;;
    --install-all) INSTALL_APK=1; INSTALL_DEB=1; INSTALL_IPA=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: 需要命令 $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd gh

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh 未登录。请先: gh auth login" >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
  echo "WARN: 当前分支是 $BRANCH（CI 发版通常只在 main/master 自动跑）" >&2
fi

# --- 1) 可选提交 ---
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ -z "$COMMIT_MSG" ]]; then
    echo "ERROR: 工作区有未提交改动。请先 commit，或加: -m \"说明\"" >&2
    git status -sb >&2
    exit 1
  fi
  echo "==> git add / commit"
  git add -A
  git reset HEAD -- dev/machine.env .device.env 2>/dev/null || true
  if git diff --cached --quiet; then
    echo "ERROR: 仅有敏感/空变更，拒绝提交。请先处理工作区。" >&2
    exit 1
  fi
  git commit -m "$COMMIT_MSG"
fi

# --- 推送前记录相对远端的路径差分（push 后差分会空）---
DIFF_BASE="origin/$BRANCH"
CHANGED=""
if git rev-parse "$DIFF_BASE" >/dev/null 2>&1; then
  CHANGED="$(git diff --name-only "$DIFF_BASE"...HEAD 2>/dev/null || true)"
fi
if [[ -z "${CHANGED// }" ]]; then
  CHANGED="$(git show --name-only --pretty='' HEAD 2>/dev/null || true)"
fi

need_app=0
need_server=0
need_admin=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    lib/*|shared/truck_ledger_editor/*|android/*|ios/*|pubspec.yaml|pubspec.lock|package_deb.sh|package_ipa.sh|control|.github/workflows/release-packages.yml)
      need_app=1 ;;
    server-php/*|scripts/deploy_server_php.sh|.github/workflows/deploy-server.yml)
      need_server=1 ;;
    admin_app/*|.github/workflows/release-admin-packages.yml)
      need_admin=1 ;;
  esac
done <<< "$CHANGED"

if [[ "$need_app$need_server$need_admin" == "000" ]]; then
  # 无路径命中时：若有待 push 的 commit，仍等三类中实际出现的 run
  echo "==> 路径未命中发版规则，将等待本 SHA 上实际出现的 Actions"
  need_app=1
  need_server=1
  need_admin=1
  WAIT_ONLY_EXISTING=1
else
  WAIT_ONLY_EXISTING=0
fi

echo "==> 触发预期: App编译上传=$need_app  后端部署=$need_server  管理端=$need_admin"

# --- 2) push ---
AHEAD=0
REMOTE_OK=0
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  REMOTE_OK=1
  AHEAD="$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)"
fi

if [[ "$REMOTE_OK" == "1" && "$AHEAD" == "0" ]]; then
  echo "==> 已与远端同步，无新 commit 可 push"
  SHA="$(git rev-parse HEAD)"
else
  echo "==> git push origin HEAD"
  git push -u origin HEAD
  SHA="$(git rev-parse HEAD)"
fi
echo "    SHA=$SHA"

# --- 3) 本机可先部署后端（与 CI 并行，加快可用）---
if [[ "$need_server" == "1" && "$LOCAL_SERVER" == "1" ]]; then
  if [[ -n "${SERVER_HOST:-}" ]]; then
    echo "==> 本机并行部署 server-php（rsync）"
    "$ROOT/one_click_server_deploy.sh" || echo "WARN: 本机 server 部署失败，仍等待 CI Deploy" >&2
  else
    echo "==> 未配置 SERVER_HOST，跳过本机 rsync（依赖 CI Deploy Server PHP）"
  fi
fi

if [[ "$DO_WAIT" != "1" ]]; then
  echo "完成（--no-wait）。请在 GitHub Actions 查看编译与上传。"
  exit 0
fi

# --- 4) 等待 CI ---
wait_workflow() {
  local name="$1"
  local optional="${2:-0}"
  local deadline=$((SECONDS + TIMEOUT_MIN * 60))
  echo "==> 等待 workflow: $name （最长 ${TIMEOUT_MIN} 分钟）"
  local run_id=""
  local seen=0
  while (( SECONDS < deadline )); do
    run_id="$(
      gh run list --commit "$SHA" --workflow "$name" --limit 5 \
        --json databaseId,status,conclusion,createdAt \
        --jq 'sort_by(.createdAt) | reverse | .[0].databaseId // empty' 2>/dev/null || true
    )"
    if [[ -z "$run_id" ]]; then
      if [[ "$optional" == "1" ]]; then
        # 可选：一段时间仍无 run 则跳过
        if (( seen == 0 && SECONDS > 120 )); then
          echo "    未触发 $name，跳过"
          return 0
        fi
      fi
      echo "    …尚未看到 run，${POLL_SEC}s 后再查"
      sleep "$POLL_SEC"
      continue
    fi
    seen=1
    local status conclusion
    status="$(gh run view "$run_id" --json status --jq .status)"
    conclusion="$(gh run view "$run_id" --json conclusion --jq '(.conclusion // "")')"
    echo "    run=$run_id status=$status conclusion=${conclusion:-—}"
    if [[ "$status" == "completed" ]]; then
      if [[ "$conclusion" == "success" ]]; then
        echo "    OK: $name"
        return 0
      fi
      echo "ERROR: $name 失败（conclusion=$conclusion）。日志: gh run view $run_id --log-failed" >&2
      gh run view "$run_id" --log-failed 2>/dev/null | tail -80 >&2 || true
      return 1
    fi
    sleep "$POLL_SEC"
  done
  echo "ERROR: 等待 $name 超时" >&2
  return 1
}

FAILED=0
OPT="$WAIT_ONLY_EXISTING"
if [[ "$need_app" == "1" ]]; then
  wait_workflow "Release Packages" "$OPT" || FAILED=1
fi
if [[ "$need_server" == "1" ]]; then
  wait_workflow "Deploy Server PHP" "$OPT" || FAILED=1
fi
if [[ "$need_admin" == "1" ]]; then
  wait_workflow "Release Admin Packages" "$OPT" || FAILED=1
fi

if [[ "$FAILED" != "0" ]]; then
  echo "ERROR: 部分 CI 未成功，中止安装步骤。" >&2
  exit 1
fi

echo "==> CI 全部成功。生产 downloads / 控制面应由「Release Packages」写回；后端应由 Deploy 或本机 rsync 更新。"

# --- 5) 可选安装 ---
if [[ "$INSTALL_APK" == "1" ]]; then
  echo "==> 安装 APK"
  "$ROOT/one_click_apk_install.sh"
fi
if [[ "$INSTALL_DEB" == "1" ]]; then
  echo "==> 安装 DEB"
  "$ROOT/one_click_deb_install.sh"
fi
if [[ "$INSTALL_IPA" == "1" ]]; then
  echo "==> 拉取 IPA"
  "$ROOT/one_click_ipa.sh"
fi

BASE="${PUBLIC_BASE_URL:-https://truck.liner0211.online}"
echo ""
echo "完成。"
echo "  APK:  ${BASE%/}/downloads/truckledger-latest.apk"
echo "  IPA:  ${BASE%/}/downloads/truckledger-latest.ipa"
echo "  DEB:  ${BASE%/}/downloads/truckledger-latest.deb"
echo "  健康: ${BASE%/}/api/health?deep=1"
