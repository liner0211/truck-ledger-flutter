#!/usr/bin/env bash
# 被其他 shell source：根据 pubspec.yaml 与 CI/本地环境设置
#   APP_BUILD_NAME / APP_BUILD_NUMBER（再传给 flutter --build-name/--build-number）
#
# 注意：勿 export FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER —— Flutter 3.32+ 将其视为
# 框架保留环境变量，在环境中设置会直接报错退出。
#
# 规则：
# - 名称：pubspec 中 version 的「+」前半段（无 + 则用整段）
# - 构建号：优先 GITHUB_RUN_NUMBER；其次 FLUTTER_BUILD_NUMBER_OVERRIDE；再次 git rev-list --count HEAD；最后用 pubspec 的 + 后半段
# - 设 SKIP_AUTO_BUILD_NUMBER=1 时不导出上述变量（由调用方决定不传参）

_flutter_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_raw="$(
  grep -m1 '^version:' "$_flutter_root/pubspec.yaml" 2>/dev/null \
    | sed -E 's/^version:[[:space:]]+//' | tr -d "'\"[:space:]" || true
)"
if [[ -z "$_raw" ]]; then
  echo "ERROR: 无法从 pubspec.yaml 解析 version" >&2
  return 1 2>/dev/null || exit 1
fi

if [[ "$_raw" == *+* ]]; then
  APP_BUILD_NAME="${_raw%%+*}"
  _pub_bn="${_raw#*+}"
else
  APP_BUILD_NAME="$_raw"
  _pub_bn="1"
fi

# 清掉可能残留的保留名，避免 flutter CLI 直接拒绝
unset FLUTTER_BUILD_NAME FLUTTER_BUILD_NUMBER 2>/dev/null || true

if [[ "${SKIP_AUTO_BUILD_NUMBER:-0}" == "1" ]]; then
  unset APP_BUILD_NAME APP_BUILD_NUMBER
  unset _flutter_root _raw _pub_bn
  return 0 2>/dev/null || exit 0
fi

if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
  APP_BUILD_NUMBER="${GITHUB_RUN_NUMBER}"
elif [[ -n "${FLUTTER_BUILD_NUMBER_OVERRIDE:-}" ]]; then
  APP_BUILD_NUMBER="${FLUTTER_BUILD_NUMBER_OVERRIDE}"
else
  APP_BUILD_NUMBER="$(
    git -C "$_flutter_root" rev-list --count HEAD 2>/dev/null || echo "$_pub_bn"
  )"
fi

export APP_BUILD_NAME
export APP_BUILD_NUMBER
# 兼容旧脚本变量名（仅 shell 变量，不 export，避免污染 flutter 环境）
FLUTTER_BUILD_NAME="$APP_BUILD_NAME"
FLUTTER_BUILD_NUMBER="$APP_BUILD_NUMBER"

echo "[build-version] APP_BUILD_NAME=$APP_BUILD_NAME APP_BUILD_NUMBER=$APP_BUILD_NUMBER" >&2
unset _flutter_root _raw _pub_bn
