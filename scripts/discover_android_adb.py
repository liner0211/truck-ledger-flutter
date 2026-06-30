#!/usr/bin/env python3
"""发现可用 Android 设备（USB 或无线 adb），向 stdout 打印 serial（如 192.168.0.128:5555）。"""
from __future__ import annotations

import ipaddress
import os
import re
import socket
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

CACHE_FILE = ".last_android_adb"
DEFAULT_PORT = int(os.environ.get("ANDROID_ADB_PORT", "5555"))
PROVIDED_IP = (os.environ.get("ANDROID_IP") or os.environ.get("ANDROID_DEVICE_IP") or "").strip()
PROVIDED_SERIAL = os.environ.get("ANDROID_SERIAL", "").strip()
VERBOSE = os.environ.get("DISCOVER_ANDROID_VERBOSE", "0") == "1"


def log(msg: str) -> None:
    if VERBOSE:
        print(msg, file=sys.stderr)


ADB_TIMEOUT_SEC = float(os.environ.get("ANDROID_ADB_CMD_TIMEOUT", "4"))


def run_adb(*args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["adb", *args],
            capture_output=True,
            text=True,
            timeout=ADB_TIMEOUT_SEC,
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(
            args=["adb", *args],
            returncode=124,
            stdout="",
            stderr="timeout",
        )


def list_ready_devices() -> list[str]:
    r = run_adb("devices")
    out: list[str] = []
    for line in r.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            out.append(parts[0])
    return out


def try_connect(host: str, port: int) -> str | None:
    serial = f"{host}:{port}"
    run_adb("disconnect", serial)
    run_adb("connect", serial)
    time.sleep(0.4)
    if serial in list_ready_devices():
        return serial
    return None


def write_cache(serial: str) -> None:
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            f.write(serial)
    except OSError:
        pass


def read_cache() -> str:
    if not os.path.exists(CACHE_FILE):
        return ""
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def get_local_network() -> ipaddress.IPv4Network:
    try:
        route = subprocess.check_output(
            ["bash", "-lc", "ip -4 route get 1.1.1.1"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        src = route.split("src ")[1].split()[0]
        return ipaddress.IPv4Network(f"{src}/24", strict=False)
    except Exception:
        pass
    host_ip = socket.gethostbyname(socket.gethostname())
    return ipaddress.IPv4Network(f"{host_ip}/24", strict=False)


def read_ip_neigh_ips() -> list[str]:
    out: list[str] = []
    try:
        txt = subprocess.check_output(["bash", "-lc", "ip neigh"], text=True, stderr=subprocess.DEVNULL)
        for line in txt.splitlines():
            ip = line.split(" ", 1)[0].strip()
            if re.match(r"^[0-9.]+$", ip):
                out.append(ip)
    except Exception:
        pass
    return out


def unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for x in items:
        if x and x not in seen:
            seen.add(x)
            out.append(x)
    return out


def port_open(ip: str, port: int, timeout: float = 0.8) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def try_serial_list(candidates: list[str], port: int) -> str | None:
    for item in unique(candidates):
        if not item:
            continue
        if ":" in item:
            if item in list_ready_devices():
                write_cache(item)
                return item
            host, _, p = item.partition(":")
            try:
                port_n = int(p)
            except ValueError:
                port_n = port
            got = try_connect(host, port_n)
            if got:
                write_cache(got)
                return got
            continue
        if item in list_ready_devices():
            write_cache(item)
            return item
        if port_open(item, port):
            got = try_connect(item, port)
            if got:
                write_cache(got)
                return got
    return None


def scan_network(port: int, skip: set[str], networks: list[ipaddress.IPv4Network]) -> str | None:
    hosts: list[str] = []
    seen_nets: set[str] = set()
    for network in networks:
        key = str(network)
        if key in seen_nets:
            continue
        seen_nets.add(key)
        hosts.extend(str(ip) for ip in network.hosts() if str(ip) not in skip)
    hosts = unique(hosts)
    open_hosts: list[str] = []
    with ThreadPoolExecutor(max_workers=64) as pool:
        futures = {pool.submit(port_open, ip, port, 0.5): ip for ip in hosts}
        for fut in as_completed(futures):
            ip = futures[fut]
            try:
                if fut.result():
                    open_hosts.append(ip)
            except Exception:
                pass
    for ip in open_hosts:
        got = try_connect(ip, port)
        if got:
            write_cache(got)
            return got
    return None


def main() -> int:
    run_adb("start-server")
    ready = list_ready_devices()

    if PROVIDED_SERIAL:
        if PROVIDED_SERIAL in ready:
            write_cache(PROVIDED_SERIAL)
            print(PROVIDED_SERIAL)
            return 0
        log(f"ANDROID_SERIAL={PROVIDED_SERIAL} 未处于 device 状态")

    if len(ready) == 1:
        write_cache(ready[0])
        print(ready[0])
        return 0

    if len(ready) > 1 and not PROVIDED_SERIAL:
        log(f"多台已连接设备: {ready}，请设置 ANDROID_SERIAL")
        return 1

    port = DEFAULT_PORT
    if PROVIDED_IP:
        host = PROVIDED_IP.split(":")[0]
        if ":" in PROVIDED_IP:
            try:
                port = int(PROVIDED_IP.split(":", 1)[1])
            except ValueError:
                pass
        got = try_connect(host, port)
        if got:
            write_cache(got)
            print(got)
            return 0
        log(f"无法连接 ANDROID_IP={PROVIDED_IP}")

    quick = [
        read_cache(),
        *read_ip_neigh_ips(),
    ]
    got = try_serial_list(quick, port)
    if got:
        print(got)
        return 0

    skip = set(quick)
    local = get_local_network()
    fallback = [
        ipaddress.IPv4Network("192.168.0.0/24"),
        ipaddress.IPv4Network("192.168.1.0/24"),
    ]
    nets = unique([str(local), *[str(n) for n in fallback]])
    networks = [ipaddress.IPv4Network(n) for n in nets]
    got = scan_network(port, skip, networks)
    if got:
        print(got)
        return 0

    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"discover error: {e}")
        sys.exit(1)
