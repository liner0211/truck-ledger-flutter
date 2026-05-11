#!/usr/bin/env bash
set -euo pipefail

# Download latest GitHub Actions iOS Runner.app artifact and package a deb locally.
# Requires: gh auth login (already authenticated for target repo)
#
# Usage:
#   ./scripts/fetch_runner_and_package_deb.sh owner/repo
# Optional:
#   RUN_ID=123456 ./scripts/fetch_runner_and_package_deb.sh owner/repo

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 owner/repo"
  exit 1
fi

REPO="$1"
RUN_ID="${RUN_ID:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "Packaging deb with existing Runner.app..."
SKIP_BUILD=1 "$ROOT_DIR/package_deb.sh"

echo "Done."
