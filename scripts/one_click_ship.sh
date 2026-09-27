#!/usr/bin/env bash
# 一键发版总控：提交(可选) →（可选临时公开）→ push → 等 CI（编译/上传 downloads/控制面/部署）→ 改回私有。
# 设备安装由 App 云端更新完成，本脚本不再 adb / SSH 装包。
#
# 用法:
#   ./one_click_ship.sh
#   ./one_click_ship.sh -m "修复某某"
#
# 依赖: git、gh（已 login）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT/scripts/github_repo.sh"

COMMIT_MSG="${SHIP_COMMIT_MSG:-}"
DO_WAIT=1
LOCAL_SERVER="${SHIP_LOCAL_SERVER:-1}"
# 等 CI 期间临时公开仓库（规避私有库 Actions 额度/账单拦截）；结束后改回私有
TEMP_PUBLIC="${SHIP_TEMP_PUBLIC:-1}"
POLL_SEC="${SHIP_POLL_SEC:-20}"
TIMEOUT_MIN="${SHIP_TIMEOUT_MIN:-90}"

REPO_SLUG=""
MADE_PUBLIC=0

usage() {
  cat <<'EOF'
一键发版：push → 等待 GitHub Actions（编译包、上传 downloads、更新控制面、部署 PHP）

  ./one_click_ship.sh [选项]

选项:
  -m, --message MSG   有未提交改动时自动 git commit（MSG 为说明）
  --no-wait           只 push，不等 CI（也不临时公开）
  --keep-private      等 CI 时保持私有（不临时公开；可能撞上 Actions 额度）
  --no-local-server   有 server-php 变更时也不本机 rsync（只靠 CI Deploy）
  -h, --help          帮助

环境变量（同名覆盖）: SHIP_COMMIT_MSG, SHIP_LOCAL_SERVER=0,
  SHIP_TEMP_PUBLIC=0, SHIP_POLL_SEC, SHIP_TIMEOUT_MIN

默认：等待 CI 时会临时把仓库改为 public，结束后（成功/失败/中断）改回 private。
客户端从云端 downloads / 控制面更新，无需本机装包脚本。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message) COMMIT_MSG="${2:-}"; shift 2 ;;
    --no-wait) DO_WAIT=0; shift ;;
    --keep-private) TEMP_PUBLIC=0; shift ;;
    --no-local-server) LOCAL_SERVER=0; shift ;;
    --install-apk|--install-deb|--install-ipa|--install-all)
      echo "ERROR: 已移除本机装包选项（$1）。请用 App 云端更新，或从生产 downloads 手动获取。" >&2
      exit 2
      ;;
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
need_cmd jq

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh 未登录。请先: gh auth login" >&2
  exit 1
fi

REPO_SLUG="$(resolve_github_repo)" || exit 1

set_repo_visibility() {
  local private_bool="$1" # true|false
  local vis="private"
  [[ "$private_bool" == "false" ]] && vis="public"
  echo "==> 仓库可见性 → $vis ($REPO_SLUG)"
  local attempt err
  for attempt in 1 2 3 4 5 6 7 8; do
    err="$(
      gh api -X PATCH "repos/$REPO_SLUG" \
        -f "private=$private_bool" \
        -f "visibility=$vis" \
        --jq '{private,visibility}' 2>&1
    )" && {
      echo "    $err"
      # GitHub 可见性变更可能异步，稍等再确认
      sleep 2
      local now
      now="$(gh api "repos/$REPO_SLUG" --jq .private)"
      if [[ "$private_bool" == "true" && "$now" == "true" ]]; then
        return 0
      fi
      if [[ "$private_bool" == "false" && "$now" == "false" ]]; then
        return 0
      fi
      echo "    …API 已返回但状态尚未同步（private=$now），重试"
    } || {
      echo "    尝试 $attempt 失败: $err"
      if ! grep -qi 'still in progress\|422' <<<"$err"; then
        return 1
      fi
    }
    sleep $((attempt * 3))
  done
  echo "ERROR: 无法将仓库设为 $vis" >&2
  return 1
}

restore_repo_private_if_needed() {
  if [[ "$MADE_PUBLIC" != "1" ]]; then
    return 0
  fi
  echo "==> CI 结束：改回私有仓库"
  if set_repo_visibility true; then
    MADE_PUBLIC=0
  else
    echo "ERROR: 改回私有失败，请手动: gh api -X PATCH repos/$REPO_SLUG -f private=true -f visibility=private" >&2
  fi
}

trap restore_repo_private_if_needed EXIT INT TERM

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

PATH_MISS=0
[[ "$need_app$need_server$need_admin" == "000" ]] && PATH_MISS=1
WAIT_ONLY_EXISTING=0
echo "==> 路径扫描: App=$need_app 后端=$need_server 管理端=$need_admin"

# --- 2) 是否已有待 push 的 commit ---
AHEAD=0
REMOTE_OK=0
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  REMOTE_OK=1
  AHEAD="$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)"
fi

# 无路径命中：用户跑 ship 即为发版 → 手动派发主 App 包（不误触后端/管理端）
if [[ "$PATH_MISS" == "1" ]]; then
  echo "==> 路径不触发自动 CI → 将手动派发「Release Packages」"
  need_app=1
fi

echo "==> 触发预期: App编译上传=$need_app  后端部署=$need_server  管理端=$need_admin"

# 无新 push、或 push 不会自动触发时，手动 workflow_dispatch
FORCE_DISPATCH=0
if [[ "$REMOTE_OK" == "1" && "$AHEAD" == "0" ]]; then
  FORCE_DISPATCH=1
elif [[ "$PATH_MISS" == "1" ]]; then
  FORCE_DISPATCH=1
fi

# --- 3) 临时公开（须在 push / 派发之前）---
if [[ "$DO_WAIT" == "1" && "$TEMP_PUBLIC" == "1" ]]; then
  priv="$(gh api "repos/$REPO_SLUG" --jq .private)"
  if [[ "$priv" == "true" ]]; then
    set_repo_visibility false
    MADE_PUBLIC=1
    echo "    （跑完 CI 后会自动改回私有；中断脚本也会尝试改回）"
  else
    echo "==> 仓库已是公开，跳过临时公开"
  fi
fi

# --- 4) push ---
DID_PUSH=0
if [[ "$REMOTE_OK" == "1" && "$AHEAD" == "0" ]]; then
  echo "==> 已与远端同步，无新 commit 可 push（将改用手动触发 CI）"
  SHA="$(git rev-parse HEAD)"
else
  echo "==> git push origin HEAD"
  git push -u origin HEAD
  DID_PUSH=1
  SHA="$(git rev-parse HEAD)"
fi
echo "    SHA=$SHA"

# --- 5) 手动派发 workflow（无新 push 或 push 不会自动触发时）---
dispatch_workflow() {
  local name="$1"
  echo "==> 手动触发 workflow: $name （ref=$BRANCH）"
  gh workflow run "$name" --ref "$BRANCH"
}

if [[ "$DO_WAIT" == "1" && "$FORCE_DISPATCH" == "1" ]]; then
  echo "==> 手动派发 CI（否则不会自动跑）"
  if [[ "$need_app" == "1" ]]; then
    dispatch_workflow "Release Packages"
  fi
  if [[ "$need_server" == "1" ]]; then
    dispatch_workflow "Deploy Server PHP"
  fi
  if [[ "$need_admin" == "1" ]]; then
    dispatch_workflow "Release Admin Packages"
  fi
  echo "    等待 Actions 注册 run…"
  sleep 8
  # 已派发则必须等成功，不能「找不到就跳过」
  WAIT_ONLY_EXISTING=0
elif [[ "$DID_PUSH" == "1" ]]; then
  echo "==> 已 push，依赖 path 过滤器自动触发 CI（不重复派发）"
fi

# --- 6) 本机可先部署后端（与 CI 并行）---
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
  echo "注意：--no-wait 不会临时公开仓库；若需公开跑 CI 请去掉该参数。"
  exit 0
fi

# --- 7) 等待 CI ---
# 兼容旧版 gh（如 Ubuntu 2.4）：无 --commit/--branch，改用 list + jq 按 headSha 过滤
wait_workflow() {
  local name="$1"
  local optional="${2:-0}"
  local deadline=$((SECONDS + TIMEOUT_MIN * 60))
  echo "==> 等待 workflow: $name （最长 ${TIMEOUT_MIN} 分钟）"
  local run_id=""
  local seen=0
  local started_after
  started_after="$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  while (( SECONDS < deadline )); do
    local runs_json
    runs_json="$(
      gh run list -w "$name" -L 30 \
        --json databaseId,status,conclusion,createdAt,headSha 2>/dev/null || true
    )"
    run_id=""
    if [[ -n "$runs_json" && "$runs_json" != "[]" ]]; then
      # 优先本 SHA；否则（手动派发后）取最近一条
      run_id="$(
        jq -r --arg sha "$SHA" \
          '[.[] | select(.headSha == $sha)] | sort_by(.createdAt) | reverse | .[0].databaseId // empty' \
          <<<"$runs_json" 2>/dev/null || true
      )"
      if [[ -z "$run_id" && "$FORCE_DISPATCH" == "1" ]]; then
        run_id="$(
          jq -r 'sort_by(.createdAt) | reverse | .[0].databaseId // empty' \
            <<<"$runs_json" 2>/dev/null || true
        )"
      fi
    fi
    if [[ -z "$run_id" ]]; then
      if [[ "$optional" == "1" ]]; then
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
    local status conclusion created
    status="$(gh run view "$run_id" --json status --jq .status)"
    conclusion="$(gh run view "$run_id" --json conclusion --jq '(.conclusion // "")')"
    created="$(gh run view "$run_id" --json createdAt --jq .createdAt)"
    # 若是很久以前的成功记录且我们刚派发，继续等更新的 run
    if [[ "$FORCE_DISPATCH" == "1" && "$status" == "completed" && -n "$started_after" ]]; then
      if [[ "$created" < "$started_after" ]]; then
        echo "    run=$run_id 过旧（$created），继续等新 run…"
        sleep "$POLL_SEC"
        continue
      fi
    fi
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

# 先改回私有，再决定成败退出（trap 也会再保一次）
restore_repo_private_if_needed

if [[ "$FAILED" != "0" ]]; then
  echo "ERROR: 部分 CI 未成功。" >&2
  exit 1
fi

echo "==> CI 全部成功。生产 downloads / 控制面应由「Release Packages」写回；后端应由 Deploy 或本机 rsync 更新。"

BASE="${PUBLIC_BASE_URL:-https://truck.liner0211.online}"
echo ""
echo "完成。客户端请走云端更新；运维可核对："
echo "  APK:  ${BASE%/}/downloads/truckledger-latest.apk"
echo "  IPA:  ${BASE%/}/downloads/truckledger-latest.ipa"
echo "  DEB:  ${BASE%/}/downloads/truckledger-latest.deb"
echo "  健康: ${BASE%/}/api/health?deep=1"
