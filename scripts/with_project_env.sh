#!/usr/bin/env bash
# VS Code / 手动包装：先加载 dev/machine.env 再执行命令。
# 若在命令前已导出 DEVICE_PASS / SUDO_PASS / DEVICE_IP / DEVICE_USER（非空），
# 则覆盖配置文件中的值，便于任务里用密码输入框临时传入。
# 用法: ./scripts/with_project_env.sh ./one_click_ipa.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
_ov_pass="${DEVICE_PASS-}"
_ov_sudo="${SUDO_PASS-}"
_ov_ip="${DEVICE_IP-}"
_ov_user="${DEVICE_USER-}"
# shellcheck disable=SC1091
source "$ROOT/scripts/project_env.sh"
[[ -n "$_ov_pass" ]] && export DEVICE_PASS="$_ov_pass"
[[ -n "$_ov_sudo" ]] && export SUDO_PASS="$_ov_sudo"
[[ -n "$_ov_ip" ]] && export DEVICE_IP="$_ov_ip"
[[ -n "$_ov_user" ]] && export DEVICE_USER="$_ov_user"
unset _ov_pass _ov_sudo _ov_ip _ov_user
exec "$@"
