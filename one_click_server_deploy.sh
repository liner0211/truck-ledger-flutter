#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/scripts/with_project_env.sh" "$ROOT/scripts/deploy_server_php.sh" "$@"
