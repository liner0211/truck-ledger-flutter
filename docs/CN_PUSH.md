# 国内系统通知（Android / iOS）

国内手机通常**没有 Google Play 服务**，本项目不使用 FCM，采用：

| 通道 | 作用 |
|------|------|
| WebSocket + **本地通知栏** | App 进程在线时（前台/后台）收到消息 → 通知栏弹出 → 点击跳转 |
| **极光 JPush** | 杀进程 / 离线仍能推到通知栏（需配置 AppKey） |

司机端与管理端均使用本地通知栏；管理端当前不集成极光（后台进程靠 WS+本地通知）。

iOS：极光走 **APNs**；本地通知同样可用。

## iOS 后台通知

iOS 在 App 进入后台后会很快挂起 WebSocket，**仅靠本地通知无法在后台持续收消息**。  
要后台/杀进程也弹通知栏：必须配置极光（iOS 走 APNs）。

Android 后台进程通常仍可维持 WS，故本地通知栏更易生效。

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

健康检查：`checks.push` / `mode=jpush` 表示服务端已配极光。  
诊断：`php bin/test_jpush.php <user_id>`

## 行为说明

- **前台**：软件内横幅（不弹系统横幅，避免干扰）
- **后台（进程在）**：本地通知栏
- **已杀进程**：仅极光可达

详见 `docs/MESSAGING.md`。
