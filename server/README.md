# 卡车记账云端后端

> **宝塔部署（推荐 PHP 版，无需 Python）**：见 [../server-php/README.md](../server-php/README.md)  
> Python 版（本地开发）：见 [DEPLOY_BAOTA.md](./DEPLOY_BAOTA.md)

简易 FastAPI 服务：多用户注册/登录（JWT）、账本 JSON 存储、附件上传下载、**Web 管理后台**。

## 快速启动（本地开发）

```bash
cd server
pip install -r requirements.txt
export ADMIN_PASSWORD="你的管理密码"   # 默认 admin123，务必修改
python main.py
```

默认监听 `http://0.0.0.0:8080`。数据保存在 `server/data/`（SQLite + 附件目录）。

## 管理后台

浏览器打开：

| 地址 | 说明 |
|------|------|
| `http://192.168.0.110:8080/admin` | Web 管理界面（用户列表、统计、删除用户） |
| `http://192.168.0.110:8080/docs` | Swagger API 文档 |
| `http://192.168.0.110:8080/api/health` | 健康检查 |

管理员密码由环境变量 **`ADMIN_PASSWORD`** 控制（默认 `admin123`，生产环境必须修改）。

## 放行端口（WSL2 / 局域网）

手机访问 PC 上的后端，需放行 **8080**：

```bash
./scripts/open_server_port.sh
```

脚本会尝试：
1. WSL 内 `ufw allow 8080`（需 sudo）
2. Windows 防火墙入站规则
3. WSL2 `portproxy`（把 Windows `0.0.0.0:8080` 转发到 WSL）

若脚本提示权限不足，在 **Windows 管理员 PowerShell** 中手动执行：

```powershell
New-NetFirewallRule -DisplayName "Truck Ledger TCP 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
# WSL IP 可在 WSL 内执行 hostname -I 查看，例如 172.x.x.x
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=<WSL_IP> connectport=8080
```

## 后端 + 管理界面：语言选型建议

| 语言/方案 | 适合场景 | 优点 | 缺点 |
|-----------|----------|------|------|
| **Python（FastAPI + Jinja2）** ✅ 当前方案 | 已有 Python API、小团队、快速迭代 | 与 API 同进程、零额外运行时、模板简单 | 复杂 SPA 交互不如前后端分离 |
| **Go（Gin/Echo + embed HTML）** | 要单文件部署、高并发 | 编译成一个二进制、内存占用低 | 需重写或维护第二套服务 |
| **Node.js（Express + React/Vue Admin）** | 需要丰富后台 UI（图表、权限树） | 生态成熟、组件库多 | 多一层 Node 进程、部署更重 |
| **PHP（Laravel Filament / AdminLTE）** | 传统虚拟主机、运维熟悉 LAMP | 后台脚手架极快 | 与现有 FastAPI 需拆服务或反向代理 |

**推荐**：本项目 API 已是 Python，继续用 **FastAPI 同进程挂载 Jinja2 管理页** 成本最低；若以后用户量很大或要复杂运营后台，再考虑 **Go 独立网关** 或 **React Admin 前后端分离**。

## API 概览

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查 |
| POST | `/api/auth/register` | 注册 `{username, password}` |
| POST | `/api/auth/login` | 登录 |
| GET | `/api/ledger` | 拉取账本（需 Bearer Token） |
| PUT | `/api/ledger` | 上传账本 `{rounds: [...]}` |
| GET/POST | `/api/attachments/{filename}` | 下载/上传 JPEG 附件 |

## 手机连接说明

1. 电脑与手机在同一 Wi‑Fi。
2. PC 局域网 IP 如 `192.168.0.110`。
3. App 登录页服务器地址：`http://192.168.0.110:8080`
4. **Android 模拟器**：`http://10.0.2.2:8080`

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | `8080` | 监听端口 |
| `JWT_SECRET` | 开发用固定串 | 生产必改 |
| `ADMIN_PASSWORD` | `admin123` | 管理后台密码 |

## 同步策略

- App 本地修改后自动上传（后台）。
- 「智能同步」：比较本机与云端 `updated_at`，较新一方胜出。
- 附件随账本 JSON 中引用的文件名一并上传/下载。
