#!/usr/bin/env bash
# 一键：拉取 CI 已编译的 IPA（禁止本机 flutter build）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/github_repo.sh"

if [[ $# -ge 1 ]]; then
  export GITHUB_REPO="$1"
fi

echo "[一键 ipa] 拉取 CI 编译的 IPA…"
OUT="$("$ROOT_DIR/scripts/fetch_ci_release_asset.sh" ipa "$ROOT_DIR/ipa-out/Runner.ipa")"
echo "[一键 ipa] 完成: $(echo "$OUT" | tail -1)"
