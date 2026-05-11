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
#   SKIP_SHA_CHECK=1    不对比本地 git HEAD 与 CI 产物提交（默认会不一致时警告）

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

# 一键任务打 deb/ipa 用的是「CI 里已编好的 Runner.app」，不是本机未提交的 Dart 改动。
if [[ "${SKIP_SHA_CHECK:-0}" != "1" ]]; then
  ci_sha="$(gh run view "$RUN_ID" --repo "$REPO" --json headSha --jq '.headSha' 2>/dev/null || true)"
  local_sha="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "$ci_sha" && -n "$local_sha" && "$ci_sha" != "$local_sha" ]]; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "  警告：当前本地提交与本次下载的 CI 产物不一致" >&2
    echo "  本地 HEAD: $local_sha" >&2
    echo "  CI 构建:   $ci_sha" >&2
    echo "  deb/ipa 内嵌的是 CI 上的代码，不包含你尚未推送或未由 CI 构建的修改。" >&2
    echo "  正确做法：git push 后等待「iOS Runner.app Build」成功，再运行一键任务；" >&2
    echo "  或在 Mac+Xcode 本机执行 flutter build ios 后直接用 package_deb.sh / package_ipa.sh。" >&2
    echo "  忽略本警告继续：SKIP_SHA_CHECK=1 ..." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
  fi
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
