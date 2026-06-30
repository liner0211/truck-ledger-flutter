# 宝塔面板部署指南

把后端从 **WSL 本机** 迁到 **真实 Linux 服务器（宝塔）**，可彻底避免 WSL2 的网络转发、Windows 防火墙、WSL IP 变动等问题。

---

## 一、为什么 WSL 上手机经常连不上？

| 问题 | 说明 |
|------|------|
| 网络隔离 | WSL2 在独立虚拟网段（如 `172.x.x.x`），局域网设备访问的是 **Windows 的 IP**（如 `192.168.0.110`），需额外 **portproxy** 转发到 WSL |
| Windows 防火墙 | 入站 8080 默认可能被拦截，需管理员权限放行 |
| IP 会变 | WSL 重启后内网 IP 可能变化，portproxy 失效 |
| 不稳定 | 电脑休眠、WSL 未启动、后端进程退出都会导致手机连不上 |

**真实服务器**：进程直接监听 `0.0.0.0` 或通过 Nginx 反代，公网/局域网访问路径简单，更适合长期给 App 用。

---

## 二、部署前准备

### 1. 服务器要求

- 系统：CentOS 7+ / Ubuntu 20+ / Debian 10+（宝塔常见环境）
- 内存：≥ 1GB 即可（本项目很轻量）
- 已安装 **宝塔 Linux 面板**

### 2. 需要上传的目录

只需上传项目中的 **`server/`** 整个文件夹，包含：

```
server/
├── main.py
├── admin_routes.py
├── requirements.txt
├── templates/
│   ├── admin_login.html
│   └── admin_dashboard.html
└── data/          # 首次可不上传，运行后自动创建
```

上传方式任选：

- 宝塔 **文件** → 上传到 `/www/wwwroot/truck-ledger-api/`
- 或 Git：`git clone` 整个仓库后只用 `server/` 子目录

### 3. 域名（推荐）或 IP

- **推荐**：`api.你的域名.com` + HTTPS（宝塔一键 SSL）
- **也可**：直接用服务器公网 IP，如 `http://123.45.67.89`

---

## 三、宝塔安装依赖

### 1. 安装软件（宝塔 → 软件商店）

- **Nginx**（必装）
- **Python 项目管理器**（推荐，宝塔自带）  
  若没有该插件，可用 **Supervisor** + 命令行启动（见下文「方式 B」）

### 2. SSH 进入服务器，创建虚拟环境

```bash
cd /www/wwwroot/truck-ledger-api/server   # 按你的实际路径修改

python3 -m venv venv
source venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

验证：

```bash
python -c "import main; print('ok')"
```

---

## 四、配置环境变量（必做）

在服务器上创建 `/www/wwwroot/truck-ledger-api/server/.env`（或写入 Supervisor / 宝塔 Python 项目的环境变量）：

```bash
PORT=8080
JWT_SECRET=请换成至少32位随机字符串
ADMIN_PASSWORD=请换成强密码
```

生成随机 JWT_SECRET 示例：

```bash
openssl rand -hex 32
```

**务必修改** `JWT_SECRET` 和 `ADMIN_PASSWORD`，不要用默认的 `admin123`。

---

## 五、启动服务

### 方式 A：宝塔「Python 项目管理器」（推荐）

1. 软件商店 → 安装 **Python 项目管理器**
2. 添加项目：
   - 项目名称：`truck-ledger-api`
   - 路径：`/www/wwwroot/truck-ledger-api/server`
   - Python 版本：3.10+
   - 启动方式：**uvicorn**
   - 启动文件/命令：

     ```
     main:app
     ```

   - 绑定：`127.0.0.1:8080`（只本机监听，对外由 Nginx 代理）
   - 环境变量：填入上面的 `JWT_SECRET`、`ADMIN_PASSWORD`、`PORT`

3. 启动项目，日志无报错即可。

若界面要求完整启动命令，填：

```bash
/www/wwwroot/truck-ledger-api/server/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8080 --workers 2
```

> 生产环境 **不要** 使用 `python main.py`（带 `--reload`，仅适合开发）。

### 方式 B：Supervisor（无 Python 项目管理器时）

宝塔 → 软件商店 → **Supervisor** → 添加守护进程：

| 项 | 值 |
|----|-----|
| 名称 | truck-ledger-api |
| 运行目录 | `/www/wwwroot/truck-ledger-api/server` |
| 启动命令 | `/www/wwwroot/truck-ledger-api/server/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8080 --workers 2` |
| 环境变量 | `JWT_SECRET=...` `ADMIN_PASSWORD=...` |

保存后启动，并设置 **开机自启**。

---

## 六、Nginx 反向代理

### 1. 宝塔添加网站

- **网站** → **添加站点**
- 域名：`api.你的域名.com`（或填公网 IP）
- 根目录随意（如 `/www/wwwroot/truck-ledger-api`），**不必**放 PHP

### 2. 配置反向代理

站点 → **设置** → **反向代理** → **添加反向代理**：

- 代理名称：`truck-ledger-api`
- 目标 URL：`http://127.0.0.1:8080`
- 发送域名：`$host`

或手动编辑 Nginx 配置，在 `server { ... }` 内加入：

```nginx
client_max_body_size 25m;

location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 300s;
    proxy_connect_timeout 60s;
}
```

> `client_max_body_size 25m` 用于附件上传（单文件上限 20MB）。

### 3. HTTPS（强烈推荐）

站点 → **SSL** → **Let's Encrypt** 申请免费证书 → 开启 **强制 HTTPS**。

完成后访问：

- 管理后台：`https://api.你的域名.com/admin`
- 健康检查：`https://api.你的域名.com/api/health`
- API 文档：`https://api.你的域名.com/docs`

---

## 七、放行防火墙

1. **云厂商安全组**（阿里云/腾讯云等）：入站放行 **80**、**443**（若只用 IP+8080 则放行 8080，不推荐）
2. **宝塔安全**：面板 → **安全** → 放行 80、443
3. 无需再配置 WSL portproxy

---

## 八、App 端修改服务器地址

部署完成后，在手机 App **登录页** 填写：

```
https://api.你的域名.com
```

若暂时只用 IP（无 SSL）：

```
http://你的公网IP
```

（通过 Nginx 80 端口反代，**不要**写 `:8080`，8080 只在本机 `127.0.0.1` 监听。）

也可改代码默认值（`lib/state/auth_controller.dart` 的 `defaultServerUrl`）后重新打包 APK。

---

## 九、数据目录与备份

运行时数据在：

```
/www/wwwroot/truck-ledger-api/server/data/
├── truck_ledger.db      # SQLite 用户与账本
└── attachments/         # 各用户附件
```

**宝塔计划任务** → 定期打包备份 `data/` 目录（建议每天或每周）。

---

## 十、部署验证清单

在服务器上：

```bash
curl -s http://127.0.0.1:8080/api/health
# 期望: {"status":"ok"}
```

在你自己的电脑浏览器：

```bash
curl -s https://api.你的域名.com/api/health
```

手机 App：

1. 登录页填 `https://api.你的域名.com`
2. 注册/登录
3. 「账号与同步」→ **测试连接** 显示正常

---

## 十一、常见问题

### 502 Bad Gateway

- Python 项目未启动 → 检查 Supervisor / Python 项目管理器
- 端口不对 → 确认 uvicorn 监听 `127.0.0.1:8080`

### 413 Request Entity Too Large

- Nginx 增加 `client_max_body_size 25m;`

### 注册/登录 500，日志有 bcrypt 相关错误

```bash
pip install passlib[bcrypt] bcrypt
```

### App 提示无法连接

- 域名是否 HTTPS 与证书有效
- 云安全组是否放行 443
- 服务器地址不要带末尾 `/`，应为 `https://api.xxx.com`

### 管理后台密码

- 由环境变量 `ADMIN_PASSWORD` 控制，修改后需 **重启** Python 项目

---

## 十二、与 WSL 开发环境对比

| | WSL 本机 | 宝塔真实服务器 |
|--|----------|----------------|
| 手机访问 | 需 portproxy + 防火墙 | 域名/IP 直接访问 |
| 稳定性 | 依赖 PC 开机 | 7×24 运行 |
| HTTPS | 难配 | 宝塔一键 SSL |
| 适用 | 临时调试 | **正式使用推荐** |

本地仍可继续用 WSL 开发；正式给 App 同步请用宝塔部署的地址。
