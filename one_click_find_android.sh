#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/scripts/find_android_device.sh" "$@"
