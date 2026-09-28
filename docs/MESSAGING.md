# 站内信与客服会话关系

两套通道，职责分离。

## 1. 站内通知（inbox / `messages`）

| 方向 | Admin → 用户（全体广播或指定用户） |
|------|-----------------------------------|
| 用户 | 查看、标记已读、**回复**（线程） |
| 管理端 | 发送、查看**已读回执**、**强制删除**、回复线程 |
| 删除权 | **仅管理端可强制删除**；删除后用户端立即不可见（物理删除 + 附件清理） |
| 用户删除 | 不允许删除原通知 |

类型示例：`ops.broadcast`、`account.notify`、`ops.reconcile`、`account.trial_expiring`。

## 2. 客服会话（support / `support_threads`）

| 方向 | 用户 ↔ 管理员（双向聊天） |
|------|---------------------------|
| 用户 | 「联系管理员」发起/继续会话、发送消息、看已读 |
| 管理端 | 会话列表、回复、强制删除整会话或单条 |
| 指定管理员 | `app_settings.support_admin_id`：`>0` 默认指派该管理员；`0` 表示任意有 `messages.manage` 的管理员可接待 |

每用户最多一条客服线程。

## API 摘要

**用户：** `GET/POST /api/messages…`、`…/replies`；`GET /api/support/thread`、`POST /api/support/messages`

**管理端：** `GET/DELETE /api/admin/messages`、`…/replies`；`GET/POST/DELETE /api/admin/support/threads…`

权限：`messages.send` 发送通知；`messages.manage` 管理/已读/客服。

## 实时同步（WebSocket，不用 FCM）

App 与管理端登录后连接 `wss://域名/ws?token=JWT`。  
PHP 写库后向本机 `http://127.0.0.1:8765/publish` 发事件，枢纽推给在线连接，两端自动刷新列表/会话。

| 组件 | 说明 |
|------|------|
| `server-php/ws/server.js` | Node 枢纽（仅监听 127.0.0.1） |
| `bash ws/start_ws.sh` | 从 `config.php` 注入密钥并启动 |
| Nginx `location /ws` | 反代到 8765（见 `nginx.truck.liner0211.online.conf`） |

**说明：** 仅在线（App 进程保持连接）时实时；杀进程/断网后不会弹系统通知（未接 FCM）。重连后下次打开会拉最新数据。

### 服务器首次启用

1. 安装 Node.js 18+（宝塔「软件商店」或系统包）  
2. 在站点 Nginx 配置中加入 `location ^~ /ws { ... }`（参考 `server-php/nginx.truck.liner0211.online.conf`），重载 Nginx  
3. `cd /www/wwwroot/truck.liner0211.online && bash ws/start_ws.sh`  
4. 本机部署脚本会在 rsync 后尝试自动重启 WS
