# 在 Windows 管理员 PowerShell 中运行，放行 8080 并配置 WSL 端口转发
# 用法: 右键「以管理员身份运行 PowerShell」，然后:
#   cd \\wsl$\Ubuntu\home\liner0211\Code\truck_ledger_flutter\scripts
#   .\open_server_port_windows.ps1

$Port = 8080
$RuleName = "Truck Ledger TCP $Port"

$rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any
    Write-Host "已创建防火墙规则: $RuleName"
} else {
    Write-Host "防火墙规则已存在: $RuleName"
}

# 获取 WSL IP（需 WSL 正在运行）
$WslIp = (wsl hostname -I).Trim().Split(" ")[0]
if ($WslIp) {
    netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$Port 2>$null
    netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$Port connectaddress=$WslIp connectport=$Port
    Write-Host "portproxy: 0.0.0.0:$Port -> ${WslIp}:$Port"
} else {
    Write-Host "无法获取 WSL IP，请手动配置 portproxy"
}

Write-Host ""
Write-Host "完成。手机访问: http://192.168.0.110:$Port/admin"
