#!/usr/bin/env bash
set -euo pipefail

# Download latest GitHub Actions iOS Runner.app artifact and package a deb locally.
# Requires: gh auth login (already authenticated for target repo)
#
# Usage:
#   ./scripts/fetch_runner_and_package_deb.sh [owner/repo]
# 省略 owner/repo 时从 GITHUB_REPO 或 git remote origin 解析。
# Optional:
#   RUN_ID=123456 ./scripts/fetch_runner_and_package_deb.sh
#   SKIP_PACKAGE_DEB=1  仅下载并解压 Runner.app，不打 deb（供一键 ipa 使用）

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/github_repo.sh"

if [[ $# -ge 1 ]]; then
  REPO="$1"
else
  REPO="$(resolve_github_repo)" || exit 1
fi

RUN_ID="${RUN_ID:-}"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(gh run list --repo "$REPO" --workflow "iOS Runner.app Build" --limit 10 --json databaseId,status,conclusion --jq '[.[] | select(.status=="completed" and .conclusion=="success")][0].databaseId')"
fi

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  echo "ERROR: no successful run found for workflow 'iOS Runner.app Build'" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading artifact from run: $RUN_ID"
gh run download "$RUN_ID" --repo "$REPO" --name runner-app-ios --dir "$TMP_DIR"

mkdir -p "$ROOT_DIR/build/ios/iphoneos"
rm -rf "$ROOT_DIR/build/ios/iphoneos/Runner.app"
unzip -q "$TMP_DIR/Runner.app.zip" -d "$ROOT_DIR/build/ios/iphoneos"

if [[ "${SKIP_PACKAGE_DEB:-0}" == "1" ]]; then
  echo "SKIP_PACKAGE_DEB=1：已解压 Runner.app，跳过打 deb。"
else
  echo "Packaging deb with existing Runner.app..."
  SKIP_BUILD=1 "$ROOT_DIR/package_deb.sh"
fi

echo "Done."
