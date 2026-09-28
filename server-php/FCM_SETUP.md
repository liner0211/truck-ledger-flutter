# Firebase Cloud Messaging（可选）

站内信 + WebSocket 已可完整运营。系统级推送（杀进程仍弹通知）按下列步骤接入 FCM/APNs。

## 1. 服务端

在 `config.php` 增加 Legacy Server Key（或后续升级 HTTP v1）：

```php
'fcm_server_key' => '你的 FCM Server Key',
```

写库后会 **双发**：RealtimeHub（在线）+ `PushService::sendToUser`（FCM）。  
`local:` 占位 token 会自动跳过。

## 2. Flutter 客户端

1. 创建 Firebase 项目，下载：
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
2. 依赖已加入：`firebase_core`、`firebase_messaging`
3. 登录后 `PushBootstrap` 取真 token 并 `POST /api/devices/push-token`
4. 无 google-services 文件时：自动回退 `local:<deviceId>`，不影响站内信/WS；Android 不会 apply google-services 插件

Android 通知渠道：`messages`（「消息」）。  
前台：`FirebaseMessaging.onMessage` → 软件内横幅（不叠系统通知）。

## 3. 越狱 iOS 注意

越狱 deb / 非 App Store 包可能无法稳定收到 APNs。此渠道建议以**站内信 + 启动拉取**为主。

## 4. 试用到期推送

宝塔计划任务：

```bash
cd /www/wwwroot/truck.liner0211.online && php bin/notify_trial_expiring.php --days=3
```
