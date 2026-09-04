# 卡车记账 PHP 后端（宝塔部署）

纯 PHP 实现，**无需 Python、无需 Composer**，与 Flutter App API 完全兼容。

> **当前生产域名**：`https://truck.liner0211.online`（PHP 8.0）  
> 逐步部署说明：见 [DEPLOY_truck.liner0211.online.md](./DEPLOY_truck.liner0211.online.md)

## 目录结构

```
server-php/
├── public/          ← 宝塔网站「运行目录」指向这里
│   ├── index.php
│   └── .htaccess
├── lib/             ← 业务逻辑
├── templates/       ← 管理后台页面
├── config.php       ← 从 config.example.php 复制并修改
└── data/            ← 运行时自动创建（SQLite + 附件）
```

## 宝塔部署步骤（5 分钟）

### 1. 上传文件

将整个 `server-php/` 上传到服务器，例如：

```
/www/wwwroot/truck-ledger-api/
```

目录应包含 `public/`、`lib/`、`templates/` 等。

### 2. 创建配置文件

```bash
cd /www/wwwroot/truck-ledger-api
cp config.example.php config.php
```

编辑 `config.php`，**务必修改**：

```php
'jwt_secret' => '至少32位随机字符串',
'admin_password' => '你的管理后台密码',
```

### 3. 添加网站

宝塔 → **网站** → **添加站点**

| 项 | 值 |
|----|-----|
| 域名 | `api.你的域名.com` 或服务器 IP |
| 根目录 | `/www/wwwroot/truck-ledger-api/public` |
| PHP 版本 | **7.4 或 8.x**（推荐 8.0+） |

> 关键：**运行目录必须选 `public`**，不要指到上一级。

### 4. 设置目录权限

宝塔 → 网站 → 设置 → **权限**：

- `data/` 目录（若不存在，先访问一次网站会自动创建）需 **可写**
- 或 SSH 执行：

```bash
mkdir -p /www/wwwroot/truck-ledger-api/data/attachments
chown -R www:www /www/wwwroot/truck-ledger-api/data
chmod -R 755 /www/wwwroot/truck-ledger-api/data
```

### 5. Nginx 配置（重要）

站点 → **设置** → **配置文件**，在 `server { ... }` 内确认/添加：

```nginx
client_max_body_size 25m;

# API / 管理路由（须在静态 .jpg 规则之前，见 server-php/nginx.truck.liner0211.online.conf）
location ^~ /api/ {
    try_files $uri /index.php?$query_string;
}

location / {
    try_files $uri $uri/ /index.php?$query_string;
}

# App 使用 Authorization: Bearer，需传给 PHP
location ~ \.php$ {
    include enable-php-80.conf;   # 按你的 PHP 版本，可能是 enable-php-74.conf
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
}
```

保存后重载 Nginx。

### 6. SSL（推荐）

站点 → **SSL** → Let's Encrypt → 开启 **强制 HTTPS**。

### 7. 验证

浏览器访问：

- `https://api.你的域名.com/api/health` → `{"status":"ok"}`
- `https://api.你的域名.com/admin` → 管理后台登录
- `https://api.你的域名.com/app/` → **用户 Web 账本**（浏览器登录，与 App 数据同步）

### 8. App 配置

手机登录页服务器地址：

```
https://api.你的域名.com
```

不要带末尾 `/`，不要带端口号（走 443）。

---

## API 接口（与 App 一致）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查（`?deep=1` 深检） |
| GET | `/api/auth/config` | 公开配置（注册开关、试用天数等） |
| POST | `/api/auth/register` | 注册（默认试用） |
| POST | `/api/auth/login` | 登录 |
| POST | `/api/auth/change-password` | 修改密码（需登录，成功后 token 失效） |
| GET | `/api/auth/me` | 当前用户权益档案 |
| POST | `/api/app/check` | 应用控制面（停服/强更/设备） |
| GET | `/api/ledger` | 拉取账本（含 `revision`） |
| GET | `/api/ledger/revision` | 轻量版本号 |
| PUT | `/api/ledger` | 上传账本（`base_revision` 乐观锁） |
| GET/POST | `/api/attachments…` | 附件列表/上下传 |
| POST | `/api/devices/push-token` | 登记推送 Token |
| GET | `/api/messages` | 站内信 |

### 发行版能力摘要

- **控制面**：停服 / 最低版本 / 强制升级 / 离线宽限 / 全局公告
- **用户运营**：试用天数、到期只读或禁止登录、延期、转正、踢下线、设备吊销
- **同步**：`revision` 乐观锁，冲突返回 409
- **触达**：站内信必达；可选 `fcm_server_key` 推送
- **运维**：审计日志、账本自动快照、健康深检、Admin CSRF

管理后台：`/admin`（用户列表、控制面设置、广播通知、审计）。

---

## Web 云端账本（`/app/`）

与手机 App **共用同一套 API 数据**，可在浏览器查看、编辑圈次并保存到云端。

| 入口 | 说明 |
|------|------|
| `/app/` | 用户使用 **注册/登录账号** 打开自己的账本 |
| 管理后台 → **查看账本** | 管理员在已登录后台后，可打开任意用户的账本并编辑 |

**功能（与 App 对齐）：**

- 圈次列表、工资汇总、删除圈次
- 新建圈次（开始/结束时间选择器）
- 圈次详情：路线、油费/高速费/其他费用、现金支取（字段与 App 一致）
- **凭证图片**：从相册/文件添加、预览、删除（保存时自动上传云端）
- 利润与交账结算文案（与 App 相同公式）
- 高速费现金/ETC 分开记录；混合 ETC+现金 编辑时自动拆分
- 已对账 / 已发工资标记
- 点击 **保存**：先上传图片，再 `PUT /api/ledger`（与 App `pushFull` 一致）

**静态文件位置：** `public/app/`（`index.html`、`app.css`、`ledger-app.js`、`profit.js`）

部署后若 `/app/` 404，确认 Nginx `try_files` 包含 `$uri $uri/`，且 `public/app/index.html` 已上传。

---

## 数据备份

定期备份：

```
/www/wwwroot/truck-ledger-api/data/
├── truck_ledger.db
└── attachments/
```

宝塔 → **计划任务** → 压缩备份 `data/` 目录。

---

## 常见问题

### 502 / 空白页

- PHP 版本是否 7.4+
- 运行目录是否 `public/`
- 查看网站 **日志**

### App 登录 401 / 无法同步

- Nginx 是否加了 `fastcgi_param HTTP_AUTHORIZATION $http_authorization;`
- `config.php` 中 `jwt_secret` 是否已设置

### 上传附件失败

- `client_max_body_size 25m;`
- `data/attachments/` 是否可写

### 与 Python 版区别

- 无 `/docs` Swagger 页面（PHP 版未实现）
- 数据库格式相同，可迁移 `data/truck_ledger.db` 和 `attachments/`

---

## 从 Python 版迁移

若之前在 `server/data/` 有数据，复制到 PHP 目录：

```bash
cp -r /path/to/server/data/* /www/wwwroot/truck-ledger-api/data/
chown -R www:www /www/wwwroot/truck-ledger-api/data
```

SQLite 表结构一致，可直接使用。
