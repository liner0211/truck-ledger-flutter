#!/usr/bin/env bash
set -euo pipefail

# 安装已有 CI 产物 deb（不编译）：发现设备 → scp + dpkg -i。
# 先 ./one_click_deb_install.sh，或手动把 .deb 放到 packages/ / 设 DEB_FILE=。
# 依赖: python3、paramiko（pip install paramiko）
#
# Usage:
#   DEVICE_PASS=0211 ./deploy.sh
# 推荐在 dev/machine.env（或 .device.env）中配置 DEVICE_PASS 等，脚本会自动加载。
# Optional:
#   DEB_FILE=packages/xxx.deb DEVICE_IP=192.168.0.129 DEVICE_PASS=0211 ./deploy.sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# 本地配置（不入库）：优先 dev/machine.env，其次 .device.env（后者可覆盖）
# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/project_env.sh"

DEVICE_IP="${DEVICE_IP:-}"
DEVICE_USER="${DEVICE_USER:-mobile}"
DEVICE_PASS="${DEVICE_PASS:-}"
SUDO_PASS="${SUDO_PASS:-$DEVICE_PASS}"
MAKEFILE_DEFAULT_IP="$(awk -F'=' '/^THEOS_DEVICE_IP[[:space:]]*\?=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' Makefile 2>/dev/null || true)"

if [[ -z "$DEVICE_PASS" ]]; then
  echo "Error: DEVICE_PASS is required."
  echo "Example: DEVICE_PASS=0211 ./deploy.sh"
  exit 1
fi

echo "[1/3] Locating CI-built deb（禁止本机编译）..."
if [[ -n "${DEB_FILE:-}" && -f "$DEB_FILE" ]]; then
  LATEST_DEB="$DEB_FILE"
elif ls -t packages/*.deb >/dev/null 2>&1; then
  LATEST_DEB="$(ls -t packages/*.deb | head -n 1)"
else
  echo "Error: packages/ 下没有 deb。请先: ./one_click_deb_install.sh（从 CI/生产拉取）" >&2
  exit 1
fi
echo "Using deb: $LATEST_DEB"

echo "[2/3] Discovering device IP (or using provided DEVICE_IP)..."
DETECTED_IP="$(
python3 - "$DEVICE_IP" "$MAKEFILE_DEFAULT_IP" "$DEVICE_USER" "$DEVICE_PASS" <<'PY'
import ipaddress
import os
import re
import socket
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

import paramiko

provided_ip = sys.argv[1].strip()
default_ip = sys.argv[2].strip()
user = sys.argv[3]
password = sys.argv[4]
cache_file = ".last_device_ip"

# Quiet paramiko noise like "Error reading SSH protocol banner"
import logging
logging.getLogger("paramiko").setLevel(logging.CRITICAL)
logging.getLogger("paramiko.transport").setLevel(logging.CRITICAL)

def can_connect(ip: str) -> bool:
    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        cli.connect(
            hostname=ip,
            username=user,
            password=password,
            port=22,
            timeout=1.5,
            banner_timeout=1.5,
            auth_timeout=1.5,
        )
        _, stdout, _ = cli.exec_command("uname -s", timeout=3)
        out = stdout.read().decode("utf-8", errors="ignore").strip()
        cli.close()
        return out == "Darwin"
    except Exception:
        return False

def get_local_network() -> ipaddress.IPv4Network:
    try:
        route = subprocess.check_output(
            ["bash", "-lc", "ip -4 route get 1.1.1.1"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        src = route.split("src ")[1].split()[0]
        ip = ipaddress.IPv4Address(src)
        return ipaddress.IPv4Network(f"{ip}/24", strict=False)
    except Exception:
        pass

    host_ip = socket.gethostbyname(socket.gethostname())
    ip = ipaddress.IPv4Address(host_ip)
    return ipaddress.IPv4Network(f"{ip}/24", strict=False)

def read_known_host_ips():
    out = []
    path = os.path.expanduser("~/.ssh/known_hosts")
    if not os.path.exists(path):
        return out
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if not line or line.startswith("|1|"):
                continue
            host_field = line.split(" ", 1)[0]
            for item in host_field.split(","):
                item = item.strip()
                m = re.match(r"^\[([0-9.]+)\]:(\d+)$", item)
                if m:
                    out.append(m.group(1))
                elif re.match(r"^[0-9.]+$", item):
                    out.append(item)
    return out

def read_ip_neigh_ips():
    out = []
    try:
        txt = subprocess.check_output(["bash", "-lc", "ip neigh"], text=True, stderr=subprocess.DEVNULL)
        for line in txt.splitlines():
            ip = line.split(" ", 1)[0].strip()
            if re.match(r"^[0-9.]+$", ip):
                out.append(ip)
    except Exception:
        pass
    return out

def read_cached_ip():
    if not os.path.exists(cache_file):
        return ""
    try:
        with open(cache_file, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return ""

def write_cached_ip(ip: str):
    try:
        with open(cache_file, "w", encoding="utf-8") as f:
            f.write(ip)
    except Exception:
        pass

def unique_ips(ips):
    seen = set()
    out = []
    for ip in ips:
        if ip and ip not in seen:
            seen.add(ip)
            out.append(ip)
    return out

def try_ip_list(ips):
    for ip in unique_ips(ips):
        if can_connect(ip):
            write_cached_ip(ip)
            print(ip)
            sys.exit(0)

if provided_ip:
    if can_connect(provided_ip):
        write_cached_ip(provided_ip)
        print(provided_ip)
        sys.exit(0)
    print("", end="")
    sys.exit(1)

quick_candidates = [
    read_cached_ip(),
    default_ip,
    *read_known_host_ips(),
    *read_ip_neigh_ips(),
]
try_ip_list(quick_candidates)

network = get_local_network()
candidates = [str(ip) for ip in network.hosts() if str(ip) not in set(quick_candidates)]

with ThreadPoolExecutor(max_workers=24) as pool:
    futures = {pool.submit(can_connect, ip): ip for ip in candidates}
    for fut in as_completed(futures):
        ip = futures[fut]
        try:
            if fut.result():
                write_cached_ip(ip)
                print(ip)
                sys.exit(0)
        except Exception:
            pass

fallback_nets = [
    ipaddress.IPv4Network("192.168.0.0/24"),
    ipaddress.IPv4Network("192.168.1.0/24"),
]
for net in fallback_nets:
    more = [str(ip) for ip in net.hosts() if str(ip) not in set(quick_candidates)]
    with ThreadPoolExecutor(max_workers=24) as pool:
        futures = {pool.submit(can_connect, ip): ip for ip in more}
        for fut in as_completed(futures):
            ip = futures[fut]
            try:
                if fut.result():
                    write_cached_ip(ip)
                    print(ip)
                    sys.exit(0)
            except Exception:
                pass

print("", end="")
sys.exit(1)
PY
)"

if [[ -z "$DETECTED_IP" ]]; then
  echo "Error: failed to discover a reachable iOS device over SSH."
  echo "Tip: provide DEVICE_IP explicitly, e.g. DEVICE_IP=192.168.0.129 DEVICE_PASS=xxxx ./deploy.sh"
  exit 1
fi

echo "Device found: $DETECTED_IP"

# LATEST_DEB 已在步骤 1 选定
if [[ -z "${LATEST_DEB:-}" || ! -f "$LATEST_DEB" ]]; then
  echo "Error: no deb package found"
  exit 1
fi

REMOTE_DEB="/var/mobile/$(basename "$LATEST_DEB")"

echo "[3/3] Uploading and installing package..."
python3 - "$DETECTED_IP" "$DEVICE_USER" "$DEVICE_PASS" "$SUDO_PASS" "$LATEST_DEB" "$REMOTE_DEB" <<'PY'
import sys

import paramiko

host, user, password, sudo_pass, local_deb, remote_deb = sys.argv[1:7]

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

sftp = cli.open_sftp()
sftp.put(local_deb, remote_deb)
sftp.close()

commands = [
    f"echo '{sudo_pass}' | sudo -S dpkg -i {remote_deb}",
    f"echo '{sudo_pass}' | sudo -S uicache -a",
]

for cmd in commands:
    print(f"$ {cmd}")
    _, stdout, stderr = cli.exec_command(cmd, timeout=180)
    out = stdout.read().decode("utf-8", errors="ignore").strip()
    err = stderr.read().decode("utf-8", errors="ignore").strip()
    code = stdout.channel.recv_exit_status()
    if out:
        print(out)
    if err:
        print(err)
    if code != 0:
        cli.close()
        raise SystemExit(code)

cli.close()
print("Install finished.")
PY

echo "Done. App deployed to $DETECTED_IP"
