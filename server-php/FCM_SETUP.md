# Firebase Cloud Messaging（可选）

站内信已可完整运营。若需要系统级推送通知，按下列步骤接入 FCM。

## 1. 服务端

在 `config.php` 增加 Legacy Server Key（或后续升级 HTTP v1）：

```php
'fcm_server_key' => '你的 FCM Server Key',
```

管理后台「远程通知」会：

1. 写入站内信（必达）
2. 若配置了 key，则向 `push_tokens` 表中的设备发 FCM

## 2. Flutter 客户端（概要）

1. 创建 Firebase 项目，下载 `google-services.json` / `GoogleService-Info.plist`
2. 添加依赖：`firebase_core`、`firebase_messaging`
3. 获取 FCM token 后调用已有接口：

```dart
await messagesApi.registerPushToken(
  deviceId: deviceId,
  token: fcmToken, // 替换当前的 local:<deviceId>
  platform: 'android', // 或 ios
);
```

现有 `InboxService.registerPushChannel` 已支持传入 `fcmToken` 参数；未集成 Firebase 时使用 `local:` 占位，不影响站内信。

## 3. 越狱 iOS 注意

越狱 deb / 非 App Store 包可能无法稳定收到 APNs。此渠道建议以**站内信 + 启动拉取**为主。

## 4. 试用到期推送

宝塔计划任务：

```bash
cd /www/wwwroot/truck.liner0211.online && php bin/notify_trial_expiring.php --days=3
```
