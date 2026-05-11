#!/usr/bin/env bash
# 供其他脚本 source：按顺序加载 dev/machine.env、.device.env（后者可覆盖前者）。
# 并可将 FLUTTER_BIN_PATH 加入 PATH（请指向 flutter 的 bin 目录，例如 /opt/flutter/bin）。

_truck_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for _truck_env in "$_truck_root/dev/machine.env" "$_truck_root/.device.env"; do
  [[ -f "$_truck_env" ]] || continue
  set -a
  # shellcheck disable=SC1091
  source "$_truck_env"
  set +a
done
if [[ -n "${FLUTTER_BIN_PATH:-}" ]]; then
  export PATH="$FLUTTER_BIN_PATH:$PATH"
fi
unset _truck_root _truck_env
