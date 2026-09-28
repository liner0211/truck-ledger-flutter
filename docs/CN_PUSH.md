# 国内系统通知（Android / iOS）

国内手机通常**没有 Google Play 服务**，FCM 不可用。本项目采用：

| 通道 | 作用 |
|------|------|
| WebSocket + **本地通知栏** | App 进程在线时（前台/后台）收到消息 → 通知栏弹出 → 点击跳转 |
| **极光 JPush** | 杀进程 / 离线仍能推到通知栏（需配置 AppKey） |
| FCM | 可选备用（有 GMS 的设备） |

iOS 不依赖 Google：极光走 **APNs**；本地通知同样可用。

## 立刻可用（无需极光）

更新 App 后：

1. 允许通知权限  
2. 保持登录（WebSocket 连上）  
3. 管理端发站内信 / 客服 / 聊天  
4. **切到桌面或其它 App**（不要杀进程）→ 通知栏应出现消息  
5. 点击通知 → 进入对应会话/详情  

## 杀进程也要收到（配置极光）

1. 注册 [极光推送](https://www.jiguang.cn/) 应用，包名 `com.liner0211.truckledger`  
2. 拿到 **AppKey**、**Master Secret**  
3. 写入服务器 `config.php`（rsync 不会覆盖）：

```php
'jpush_app_key' => '你的AppKey',
'jpush_master_secret' => '你的MasterSecret',
'jpush_apns_production' => false, // 正式 IPA 改为 true
```

4. iOS：Xcode 打开 Push Notifications；在极光后台上传 APNs 证书/Auth Key  
5. （推荐）CI/本机构建传入同一 AppKey：

```bash
export JPUSH_APPKEY=你的AppKey
# 或 flutter build 时 -PJPUSH_APPKEY=...
```

6. 重新发版安装 → 登录 → 服务器 `push_tokens` 中应出现 `jpush:…`  
7. 杀进程后发消息，通知栏应弹出  

健康检查：`checks.fcm` / push 状态里 `mode=jpush` 表示服务端已配极光。

## 行为说明

- **前台**：软件内横幅 + 通知栏（可点）  
- **后台（进程在）**：本地通知栏  
- **已杀进程**：仅极光（或 FCM）可达  

详见 `docs/MESSAGING.md`。
