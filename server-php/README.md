# 卡车记账 PHP 后端

纯 PHP，**无需 Composer**，与 Flutter App API 兼容。

> **生产域名**：`https://truck.liner0211.online`（PHP 8.0）  
> **逐步部署（权威）**：[DEPLOY_truck.liner0211.online.md](./DEPLOY_truck.liner0211.online.md)  
> DNS：[DNSPOD.md](./DNSPOD.md) · 可选推送：[FCM_SETUP.md](./FCM_SETUP.md)  
> 本机一键：`./one_click_server_deploy.sh`（保留远端 `config.php` / `data/` / `downloads/`）

## 目录结构

```
server-php/
├── public/          ← 宝塔网站「运行目录」指向这里
│   ├── index.php
│   ├── app/         ← Web 云端账本
│   └── downloads/   ← CI 上传的 APK/IPA/DEB
├── lib/             ← 业务逻辑
├── templates/       ← 管理后台页面
├── config.php       ← 从 config.example.php 复制（勿提交）
└── data/            ← 运行时数据（SQLite + 附件，勿提交）
```

生产站点根示例：`/www/wwwroot/truck.liner0211.online/`（Web root = `public/`）。新环境部署步骤以 [DEPLOY_*.md](./DEPLOY_truck.liner0211.online.md) 为准，勿使用过时路径示例。

## 发行版能力摘要

- **控制面**：停服 / 最低版本 / 强制升级 / 离线宽限 / 全局公告
- **用户运营**：试用、到期只读或禁登、延期、转正、踢下线、设备吊销
- **同步**：`revision` 乐观锁，冲突 409
- **触达**：站内信；可选 FCM HTTP v1（服务账号，见 FCM_SETUP）
- **运维**：审计、账本快照、健康深检 `GET /api/health?deep=1`、Admin CSRF

管理后台：`/admin`。

## API 接口（与 App 一致）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查（`?deep=1` 深检） |
| GET | `/api/auth/config` | 公开配置（注册开关、试用天数等） |
| POST | `/api/auth/register` | 注册（默认试用） |
| POST | `/api/auth/login` | 登录 |
| POST | `/api/auth/change-password` | 修改密码（需登录，成功后 token 失效） |
| GET | `/api/auth/me` | 当前用户权益档案 |
| POST | `/api/app/check` | 应用控制面 |
| GET | `/api/ledger` | 拉取账本（含 `revision`） |
| GET | `/api/ledger/revision` | 轻量版本号 |
| PUT | `/api/ledger` | 上传账本（`base_revision` 乐观锁） |
| GET/POST | `/api/attachments…` | 附件列表/上下传 |
| POST | `/api/devices/push-token` | 登记推送 Token |
| GET | `/api/messages` | 站内信列表 |
| GET/POST | `/api/messages/{id}/replies` | 站内信回复 |
| GET | `/api/support/thread` · POST `/api/support/messages` | 客服会话 |
| 消息关系说明 | [`docs/MESSAGING.md`](../docs/MESSAGING.md) | 通知 / 已读 / 强制删 / 客服 |

## Web 云端账本（`/app/`）

与手机 App **共用同一套 API 数据**。

| 入口 | 说明 |
|------|------|
| `/app/` | 用户注册/登录后打开自己的账本 |
| 管理后台 → **查看账本** | 管理员打开任意用户账本 |

功能与 App 对齐（圈次、费用、凭证图、交账/发工资标记、保存即 `PUT /api/ledger`）。静态文件：`public/app/`。

## App 与域名

**发行版 App 不向用户展示服务器地址**，内置默认云端入口。Debug / Profile 可在登录页改地址（`AuthController.defaultServerUrl`）。运维只需保证 HTTPS API 可用。

## 数据备份

定期备份站点根下 `data/`（`truck_ledger.db` + `attachments/`）。宝塔计划任务压缩即可。

## 常见问题

### 502 / 空白页

- PHP 7.4+；运行目录必须是 `public/`；查看网站日志。

### App 登录 401 / 无法同步

- Nginx 需 `fastcgi_param HTTP_AUTHORIZATION $http_authorization;`
- `config.php` 中 `jwt_secret` 已设置

### 上传附件失败

- `client_max_body_size`（建议 ≥25m）与 `max_upload_bytes` 一致
- `data/attachments/` 可写
