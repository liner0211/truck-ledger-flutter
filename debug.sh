#!/usr/bin/env bash
set -euo pipefail

# 与 TheosUIApp/TruckLedger/debug.sh 相同：SSH 上查包、打开应用、列崩溃日志。
# 依赖: python3、paramiko
#
# Usage:
#   DEVICE_PASS=0211 ./debug.sh
# Optional:
#   DEVICE_IP=192.168.0.129 DEVICE_USER=mobile DEVICE_PASS=0211 ./debug.sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/project_env.sh"

APP_NAME="${APP_NAME:-Runner}"
BUNDLE_ID="${BUNDLE_ID:-com.liner0211.truckledger}"
DEVICE_IP="${DEVICE_IP:-}"
DEVICE_USER="${DEVICE_USER:-mobile}"
DEVICE_PASS="${DEVICE_PASS:-}"
SUDO_PASS="${SUDO_PASS:-$DEVICE_PASS}"

if [[ -z "$DEVICE_PASS" ]]; then
  echo "Error: DEVICE_PASS is required."
  echo "Example: DEVICE_PASS=0211 ./debug.sh"
  exit 1
fi

if [[ -z "$DEVICE_IP" && -f ".last_device_ip" ]]; then
  DEVICE_IP="$(cat .last_device_ip)"
fi

if [[ -z "$DEVICE_IP" ]]; then
  DEVICE_IP="$(awk -F'=' '/^THEOS_DEVICE_IP[[:space:]]*\?=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' Makefile 2>/dev/null || true)"
fi

if [[ -z "$DEVICE_IP" ]]; then
  echo "Error: cannot determine DEVICE_IP."
  echo "Run deploy once or pass DEVICE_IP explicitly."
  exit 1
fi

python3 - "$DEVICE_IP" "$DEVICE_USER" "$DEVICE_PASS" "$SUDO_PASS" "$APP_NAME" "$BUNDLE_ID" <<'PY'
import sys

import paramiko

host, user, password, sudo_pass, app_name, bundle_id = sys.argv[1:7]

cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
cli.connect(
    hostname=host,
    username=user,
    password=password,
    port=22,
    timeout=10,
    banner_timeout=10,
    auth_timeout=10,
)

print(f"Connected to {user}@{host}")
print(f"App: {app_name} ({bundle_id})\n")

commands = [
    ("Package info", f"echo '{sudo_pass}' | sudo -S dpkg -s {bundle_id} || true"),
    ("Open app", f"uiopen --bundleid {bundle_id}"),
    ("Recent crash logs (common paths)",
     "ls -lt /var/mobile/Library/Logs/CrashReporter 2>/dev/null | sed -n '1,15p'; "
     "ls -lt /var/mobile/Library/Logs/CrashReporter/MobileDevice 2>/dev/null | sed -n '1,15p'; "
     "ls -lt /var/mobile/Library/Logs/DiagnosticLogs 2>/dev/null | sed -n '1,15p'; "
     "ls -lt /var/root/Library/Logs/CrashReporter 2>/dev/null | sed -n '1,15p'"),
]

for title, cmd in commands:
    print(f"== {title} ==")
    _, stdout, stderr = cli.exec_command(cmd, timeout=30)
    out = stdout.read().decode("utf-8", errors="ignore").strip()
    err = stderr.read().decode("utf-8", errors="ignore").strip()
    if out:
        print(out)
    if err:
        print(err)
    print("")

print("Note: this device environment has no usable unified 'log stream' command via SSH.")
cli.close()
PY
