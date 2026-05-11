#!/usr/bin/env bash
# 解析 GitHub owner/repo，供一键脚本与 fetch 使用。
# 优先级：显式参数 > 环境变量 GITHUB_REPO > git remote origin

resolve_github_repo() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return 0
  fi
  if [[ -n "${GITHUB_REPO:-}" ]]; then
    echo "$GITHUB_REPO"
    return 0
  fi
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    echo "ERROR: 无法解析仓库：未配置 git remote，请传入 owner/repo 或设置环境变量 GITHUB_REPO" >&2
    return 1
  fi
  local o r
  if [[ "$url" =~ github\.com:([^/]+)/(.+)\.git$ ]]; then
    o="${BASH_REMATCH[1]}"
    r="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ github\.com/([^/]+)/([^/]+) ]]; then
    o="${BASH_REMATCH[1]}"
    r="${BASH_REMATCH[2]%.git}"
  else
    echo "ERROR: 无法从 remote 解析 GitHub 仓库: $url" >&2
    return 1
  fi
  echo "$o/$r"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  resolve_github_repo "${1:-}" || exit 1
fi
