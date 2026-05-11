#!/usr/bin/env bash
# 根据 dev/machine.env 中的 GIT_* 变量写入本仓库 git config（local）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"

any=0
if [[ -n "${GIT_USER_NAME:-}" ]]; then
  git config user.name "$GIT_USER_NAME"
  any=1
fi
if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
  git config user.email "$GIT_USER_EMAIL"
  any=1
fi
if [[ -n "${GIT_REMOTE_URL:-}" ]]; then
  git remote set-url origin "$GIT_REMOTE_URL"
  any=1
fi
if [[ "$any" -eq 0 ]]; then
  echo "未设置 GIT_USER_NAME / GIT_USER_EMAIL / GIT_REMOTE_URL，跳过。请编辑 dev/machine.env" >&2
  exit 1
fi
echo "已写入本仓库本地 git 配置（git config --local）。"
git config --local --list | grep -E '^(user\.name|user\.email|remote\.origin\.url)=' || true
