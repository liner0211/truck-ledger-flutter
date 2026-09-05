#!/usr/bin/env bash
# 一键：拉取 CI 已编译的 deb → SSH 安装到越狱设备（禁止本机 flutter build）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/github_repo.sh"

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  REPO="$(resolve_github_repo)" || true
fi

echo "[一键 deb] 拉取 CI 编译的 deb…"
DEB="$("$ROOT_DIR/scripts/fetch_ci_release_asset.sh" deb)"
DEB="$(echo "$DEB" | tail -1)"

# deploy.sh 期望 packages/ 下有 deb；复制一份标准名
mkdir -p "$ROOT_DIR/packages"
cp -f "$DEB" "$ROOT_DIR/packages/com.liner0211.truckledger_ci.deb"

export SKIP_BUILD=1
export DEB_FILE="$ROOT_DIR/packages/com.liner0211.truckledger_ci.deb"
echo "[一键 deb] 安装到设备…"
exec "$ROOT_DIR/deploy.sh"
