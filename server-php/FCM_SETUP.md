# Firebase Cloud Messaging（系统通知）

Legacy Server Key **已停用**。本项目使用 **FCM HTTP v1 + 服务账号 JSON**。

包名 / Bundle ID（建 Firebase App 时必须一致）：

| 平台 | 标识 |
|------|------|
| Android | `com.liner0211.truckledger` |
| iOS | `com.liner0211.truckledger` |

## 一键目录（推荐）

把下面 3 个文件放到本机 `dev/fcm/`（已 gitignore）：

```
dev/fcm/
  fcm-service-account.json   # Firebase 服务账号私钥
  google-services.json       # Android
  GoogleService-Info.plist   # iOS（可选，仅打 IPA 时需要）
```

然后执行：

```bash
./scripts/apply_fcm_credentials.sh
```

脚本会：

1. 把服务账号 scp 到服务器 `data/fcm-service-account.json`，并写入/补齐远端 `config.php` 的 `fcm_service_account_file`
2. 复制客户端配置到 `android/app/`、`ios/Runner/`
3. 可选：把 `google-services.json` base64 写入 GitHub Secret `GOOGLE_SERVICES_JSON_BASE64`（CI 编 Release 用）
4. 跑一次健康检查

## Firebase 控制台操作（首次）

1. 打开 [Firebase Console](https://console.firebase.google.com/) → 创建或选择项目  
2. **添加 Android 应用**：包名 `com.liner0211.truckledger` → 下载 `google-services.json`  
3. **添加 iOS 应用**：Bundle ID `com.liner0211.truckledger` → 下载 `GoogleService-Info.plist`  
4. 项目设置 → **服务账号** →「生成新的私钥」→ 得到 `*-firebase-adminsdk-*.json`，改名为 `fcm-service-account.json`  
5. Google Cloud Console → API 和服务 → 启用 **Firebase Cloud Messaging API**  
6. 把 3 个文件放进 `dev/fcm/`，跑上面的脚本  

## 服务端配置

`config.php`（rsync **不会**覆盖）：

```php
'fcm_service_account_file' => 'data/fcm-service-account.json',
'fcm_project_id' => '', // 通常留空，用 JSON 内 project_id
```

健康检查：`GET /api/health?deep=1` → `checks.fcm` 应为 `configured`（HTTP v1）。

## 客户端

- 依赖：`firebase_core`、`firebase_messaging`
- 有 `google-services.json` 时 Android 自动 apply 插件；登录后上报真 FCM token
- 无配置文件时回退 `local:` 占位（仅站内信 + WS）
- Android 渠道 id：`messages`（「消息」）
- 前台：`onMessage` → 软件内横幅，避免叠系统通知

## 验证

1. 司机端登录并允许通知权限  
2. 管理端发一条站内信 / 客服回复 / 聊天消息  
3. **杀进程**后应出现系统通知栏消息  

调试：服务器 `data/` 下勿提交私钥；`push_tokens` 表中 token 不应再是 `local:` 开头。

## 试用到期推送

```bash
cd /www/wwwroot/truck.liner0211.online && php bin/notify_trial_expiring.php --days=3
```
