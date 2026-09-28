# 国内系统通知（Android / iOS）

国内手机通常**没有 Google Play 服务**，本项目不使用 FCM，采用：

| 通道 | 作用 |
|------|------|
| WebSocket + **本地通知栏** | App 进程在线时（前台/后台）收到消息 → 通知栏弹出 → 点击跳转 |
| **极光 JPush** | 杀进程 / iOS 后台仍能推到通知栏（**必须配置**） |

> **当前生产若 `checks.push=optional`**：说明远端 `config.php` 尚未填写极光，  
> **iOS 进后台/杀进程一定收不到系统通知**（系统会挂起 WS，本地通知无法接管）。

司机端与管理端均使用本地通知栏；管理端当前不集成极光（后台进程靠 WS+本地通知）。

## 必配：极光（否则 iOS 后台无通知）

1. 注册 [极光推送](https://www.jiguang.cn/) 应用，Android 包名 `com.liner0211.truckledger`，iOS Bundle Id 与工程一致  
2. 拿到 **AppKey**、**Master Secret**  
3. **SSH 改服务器** `config.php`（rsync **不会**覆盖该文件）：

```php
'jpush_app_key' => '你的AppKey',
'jpush_master_secret' => '你的MasterSecret',
'jpush_apns_production' => true, // 正式 IPA 用 true；开发包用 false
```

4. iOS：Xcode 打开 Push Notifications + Background Modes → remote notifications；在极光控制台上传 **APNs Auth Key / 证书**  
5. 健康检查：`GET /api/health?deep=1` → `checks.push` 应为 `configured`，`mode=jpush`  
6. 客户端重新登录后，库表 `push_tokens` 应出现 `jpush:…`  
7. 诊断：`php bin/test_jpush.php <user_id>`

## 行为说明

- **前台**：软件内横幅（不弹系统横幅干扰）  
- **后台（进程在，Android）**：本地通知栏（WS 仍可连通时）  
- **iOS 后台 / 已杀进程**：仅极光（APNs）可达  

详见 `docs/MESSAGING.md`。
