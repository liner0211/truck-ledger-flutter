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
