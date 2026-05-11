#!/usr/bin/env bash
set -euo pipefail

# 独立设备发现脚本：复用 deploy.sh 的自动找机逻辑（不打包、不安装）。
# Usage:
#   DEVICE_PASS=0211 ./scripts/find_device_ip.sh [--verbose]
# Optional:
#   DEVICE_IP=192.168.0.128 DEVICE_USER=mobile DEVICE_PASS=0211 ./scripts/find_device_ip.sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VERBOSE=0
if [[ "${1:-}" == "--verbose" ]]; then
  VERBOSE=1
fi

if [[ -f ".device.env" ]]; then
  # shellcheck disable=SC1091
  source ".device.env"
fi

DEVICE_IP="${DEVICE_IP:-}"
DEVICE_USER="${DEVICE_USER:-mobile}"
DEVICE_PASS="${DEVICE_PASS:-}"
MAKEFILE_DEFAULT_IP="$(awk -F'=' '/^THEOS_DEVICE_IP[[:space:]]*\?=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' Makefile 2>/dev/null || true)"

if [[ -z "$DEVICE_PASS" ]]; then
  echo "Error: DEVICE_PASS is required."
  echo "Example: DEVICE_PASS=0211 ./scripts/find_device_ip.sh"
  exit 1
fi

echo "Discovering device IP..."
DETECTED_IP="$(
python3 - "$DEVICE_IP" "$MAKEFILE_DEFAULT_IP" "$DEVICE_USER" "$DEVICE_PASS" "$VERBOSE" <<'PY'
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
verbose = sys.argv[5].strip() == "1"
cache_file = ".last_device_ip"

def vlog(msg: str):
    if verbose:
        print(msg, file=sys.stderr, flush=True)

def can_connect(ip: str) -> bool:
    vlog(f"[try] {ip}:22")
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
        vlog(f"[ok] {ip} uname={out}")
        return out == "Darwin"
    except Exception:
        vlog(f"[fail] {ip}")
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
    vlog(f"[provided] {provided_ip}")
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
vlog(f"[quick-candidates] {unique_ips(quick_candidates)}")
try_ip_list(quick_candidates)

network = get_local_network()
candidates = [str(ip) for ip in network.hosts() if str(ip) not in set(quick_candidates)]
vlog(f"[scan] local network {network} ({len(candidates)} hosts)")
with ThreadPoolExecutor(max_workers=48) as pool:
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
    vlog(f"[scan] fallback network {net} ({len(more)} hosts)")
    with ThreadPoolExecutor(max_workers=48) as pool:
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
  echo "ERROR: failed to discover a reachable iOS device over SSH."
  echo "Tip: ensure OpenSSH is running and phone + host are on same LAN."
  exit 1
fi

echo "Device found: $DETECTED_IP"
