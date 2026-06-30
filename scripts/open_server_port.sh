#!/usr/bin/env bash
# 放行卡车记账后端端口（默认 8080），适用于 WSL2 + Windows 局域网访问。
set -euo pipefail

PORT="${PORT:-8080}"
RULE_NAME="Truck Ledger TCP ${PORT}"

echo "=== 放行端口 ${PORT} ==="

# WSL 内 ufw（若有且可 sudo）
if command -v ufw >/dev/null 2>&1; then
  if sudo -n ufw status >/dev/null 2>&1; then
    echo "[WSL] ufw allow ${PORT}/tcp"
    sudo ufw allow "${PORT}/tcp" || true
    sudo ufw reload 2>/dev/null || true
  else
    echo "[WSL] 跳过 ufw（需要 sudo 密码，可手动: sudo ufw allow ${PORT}/tcp）"
  fi
fi

# Windows 防火墙 + WSL 端口转发（从 WSL 调用 PowerShell）
if command -v powershell.exe >/dev/null 2>&1; then
  echo "[Windows] 添加入站防火墙规则..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
    \$rule = Get-NetFirewallRule -DisplayName '${RULE_NAME}' -ErrorAction SilentlyContinue
    if (-not \$rule) {
      New-NetFirewallRule -DisplayName '${RULE_NAME}' -Direction Inbound -Protocol TCP -LocalPort ${PORT} -Action Allow -Profile Any | Out-Null
      Write-Host '已创建防火墙规则: ${RULE_NAME}'
    } else {
      Write-Host '防火墙规则已存在: ${RULE_NAME}'
    }
  " || echo "[Windows] 防火墙规则需管理员 PowerShell 手动执行（见 server/README.md）"

  echo "[Windows] 配置 WSL 端口转发 localhost:${PORT} ..."
  WSL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "${WSL_IP:-}" ]]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
      netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=${PORT} 2>\$null | Out-Null
      netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=${PORT} connectaddress=${WSL_IP} connectport=${PORT}
      Write-Host 'portproxy: 0.0.0.0:${PORT} -> ${WSL_IP}:${PORT}'
    " || echo "[Windows] portproxy 需管理员权限"
  fi
else
  echo "[Windows] 未找到 powershell.exe，请在 Windows 管理员 PowerShell 中手动放行 ${PORT}"
fi

echo ""
echo "完成。手机可访问: http://<PC局域网IP>:${PORT}"
echo "管理后台: http://<PC局域网IP>:${PORT}/admin"
echo "健康检查: curl http://127.0.0.1:${PORT}/api/health"
