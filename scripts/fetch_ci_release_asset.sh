#!/usr/bin/env bash
# 从 GitHub Release 或生产 downloads 拉取已由 CI 编译的安装包（禁止本机 flutter build）。
# 用法:
#   ./scripts/fetch_ci_release_asset.sh apk [输出路径]
#   ./scripts/fetch_ci_release_asset.sh deb [输出路径]
#   ./scripts/fetch_ci_release_asset.sh ipa [输出路径]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/project_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/github_repo.sh"

KIND="${1:-}"
OUT="${2:-}"
if [[ -z "$KIND" ]]; then
  echo "用法: $0 apk|deb|ipa [输出文件]" >&2
  exit 1
fi

PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://truck.liner0211.online}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"

case "$KIND" in
  apk)
    SERVER_URL="${PUBLIC_BASE_URL}/downloads/truckledger-latest.apk"
    NAME_GLOB='*.apk'
    ASSET_REGEX='truckledger-.*-release\.apk$|\.apk$'
    DEFAULT_OUT="$ROOT_DIR/dist/truckledger-latest.apk"
    ;;
  deb)
    SERVER_URL="${PUBLIC_BASE_URL}/downloads/truckledger-latest.deb"
    NAME_GLOB='*.deb'
    ASSET_REGEX='\.deb$'
    DEFAULT_OUT="$ROOT_DIR/packages/truckledger-latest.deb"
    ;;
  ipa)
    SERVER_URL="${PUBLIC_BASE_URL}/downloads/truckledger-latest.ipa"
    NAME_GLOB='*.ipa'
    ASSET_REGEX='truckledger-.*\.ipa$|\.ipa$'
    DEFAULT_OUT="$ROOT_DIR/ipa-out/Runner.ipa"
    ;;
  *)
    echo "未知类型: $KIND（apk|deb|ipa）" >&2
    exit 1
    ;;
esac

OUT="${OUT:-$DEFAULT_OUT}"
mkdir -p "$(dirname "$OUT")"

download_ok=0
if [[ -n "$SERVER_URL" ]] && command -v curl >/dev/null 2>&1; then
  echo "[fetch] 尝试生产下载: $SERVER_URL"
  if curl -fsSL --max-time 120 -o "$OUT.partial" "$SERVER_URL"; then
    mv -f "$OUT.partial" "$OUT"
    download_ok=1
    echo "[fetch] 已保存: $OUT"
  else
    rm -f "$OUT.partial"
    echo "[fetch] 生产下载失败，改试 GitHub Release…"
  fi
fi

if [[ "$download_ok" != "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: 需要 gh（已登录）或可访问的生产下载地址" >&2
    exit 1
  fi
  REPO="$(resolve_github_repo)" || exit 1
  echo "[fetch] 从 GitHub Releases 拉取最新成功包: $REPO"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  # 取最新 release 的匹配资产
  TAG="$(gh release list --repo "$REPO" --limit 5 --json tagName,isDraft,isPrerelease \
    --jq '[.[]|select(.isDraft==false)][0].tagName' 2>/dev/null || true)"
  if [[ -z "$TAG" || "$TAG" == "null" ]]; then
    echo "ERROR: 仓库无可用 Release，请先 push 触发 Release Packages" >&2
    exit 1
  fi
  echo "[fetch] release tag: $TAG"
  gh release download "$TAG" --repo "$REPO" --dir "$TMP" --pattern "$NAME_GLOB" 2>/dev/null \
    || gh release download "$TAG" --repo "$REPO" --dir "$TMP"
  FOUND="$(find "$TMP" -type f | python3 -c "
import re,sys
rx=re.compile(r'''$ASSET_REGEX''')
cands=[]
for line in sys.stdin:
  p=line.strip()
  if p and rx.search(p):
    cands.append(p)
print(cands[0] if cands else '')
")"
  if [[ -z "$FOUND" || ! -f "$FOUND" ]]; then
    echo "ERROR: Release $TAG 中未找到 $KIND 资产" >&2
    find "$TMP" -type f >&2 || true
    exit 1
  fi
  cp -f "$FOUND" "$OUT"
  echo "[fetch] 已保存: $OUT  (from $FOUND)"
fi

ls -lh "$OUT"
echo "$OUT"
