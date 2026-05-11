#!/usr/bin/env bash
# 一键：从 GitHub Actions 拉取最新成功的 Runner.app → 生成 ipa（ipa-out/Runner.ipa）
# 依赖: gh auth login、同一局域网无需额外配置（仓库默认识别 git remote）
# 用法:
#   ./scripts/one_click_ipa.sh
#   ./scripts/one_click_ipa.sh owner/repo
#   GITHUB_REPO=owner/repo ./scripts/one_click_ipa.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/github_repo.sh"

REPO="$(resolve_github_repo "${1:-}")" || exit 1

echo "[一键 IPA] 仓库: $REPO"
export SKIP_PACKAGE_DEB=1
./scripts/fetch_runner_and_package_deb.sh "$REPO"

echo "[一键 IPA] 正在从 Runner.app 打包 ipa..."
SKIP_BUILD=1 ./package_ipa.sh

echo "[一键 IPA] 完成。"
