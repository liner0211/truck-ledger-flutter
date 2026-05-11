#!/usr/bin/env bash
# 一键：从 GitHub Actions 拉取最新成功的 Runner.app → 打 deb → 发现设备并安装
# 依赖: gh auth login、python3 + paramiko、设备 SSH（密码见下方）
# 推荐在项目根复制 dev/machine.env.example → dev/machine.env 填写 DEVICE_PASS 等。
# 用法:
#   ./scripts/one_click_deb_install.sh
#   ./scripts/one_click_deb_install.sh owner/repo
#   DEVICE_PASS=你的密码 ./scripts/one_click_deb_install.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/github_repo.sh"

REPO="$(resolve_github_repo "${1:-}")" || exit 1

echo "[一键 deb 安装] 仓库: $REPO"
./scripts/fetch_runner_and_package_deb.sh "$REPO"

echo "[一键 deb 安装] 正在安装到设备（SKIP_BUILD=1，不重复 flutter 编译）..."
export SKIP_BUILD=1
./deploy.sh

echo "[一键 deb 安装] 完成。"
