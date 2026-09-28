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

**管理端：** `GET/DELETE /api/admin/messages`、`…/replies`；`GET/POST/DELETE /api/admin/support/threads…`；`GET /api/admin/ws-status`

权限：`messages.send` 发送通知；`messages.manage` 管理/已读/客服。

## 实时同步（WebSocket，不用 FCM）

App、管理端 App、网页后台登录后连接 `wss://域名/ws?token=JWT`。  
PHP 写库后向本机 `http://127.0.0.1:8765/publish` 发事件，枢纽推给在线连接，两端自动刷新列表/会话（无需退出重进）。

| 组件 | 说明 |
|------|------|
| `server-php/ws/server.js` | Node 枢纽（仅监听 127.0.0.1） |
| `bash ws/setup_baota_ws.sh` | **推荐**：装 Node、注入 Nginx `/ws`、systemd 托管 |
| `bash ws/start_ws.sh` | 从 `config.php` 注入密钥并启动/重启 |
| Nginx `location /ws` | 反代到 8765（脚本可自动写入宝塔站点 conf） |
| `GET /api/health?deep=1` | `checks.websocket` / `websocket` 字段 |
| 网页后台 | 顶栏 WS 状态 + 站内信/客服实时列表 |

**说明：** 仅在线（进程保持连接）时实时；杀进程/断网后不会弹系统通知（未接 FCM）。重连后会自动拉最新数据。

### 服务器启用（部署脚本已自动）

`./one_click_server_deploy.sh` / `scripts/deploy_server_php.sh` 在 rsync 后会执行 `ws/setup_baota_ws.sh`：

1. 检测/安装 Node.js 20（宝塔目录或官方二进制）
2. 向宝塔 Nginx 站点 conf 注入 `location ^~ /ws`
3. 写入 systemd `truck-ledger-ws` 或回退 nohup
4. 健康检查 `http://127.0.0.1:8765/health`

手动：`cd /www/wwwroot/truck.liner0211.online && bash ws/setup_baota_ws.sh`
