#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/scripts/with_project_env.sh" \
  "$(cd "$(dirname "$0")" && pwd)/scripts/one_click_ship.sh" "$@"
