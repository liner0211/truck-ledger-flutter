# 国内系统通知（Android / iOS）

国内手机通常**没有 Google Play 服务**，本项目不使用 FCM，采用：

| 通道 | 作用 |
|------|------|
| WebSocket + **本地通知栏** | App 进程在线时收到消息 → 通知栏 |
| **极光 JPush** | 杀进程 / **iOS 后台**仍能推到通知栏（必须配置） |

> 生产健康检查若 `checks.push=optional`：远端尚未填极光 → **iOS 后台一定无系统通知**。

---

## CI 编 IPA 时如何配极光（推荐顺序）

本仓库 **Release Packages** 的 iOS 是 `flutter build ios --release --no-codesign` 再打成 IPA。  
**极光 AppKey 不写进 IPA 源码**，而是 App 登录后由服务端 `/api/app/check` 下发。因此：

| 要做的事 | 和 CI 的关系 |
|----------|--------------|
| 服务器 `config.php` 填 `jpush_*` | **与 CI 无关**，SSH 改生产机即可（rsync 不覆盖） |
| 极光控制台 + Apple APNs | **与 CI 无关**，网页操作 |
| GitHub Secret `JPUSH_APPKEY` | **仅 Android** manifest 占位；iOS 不需要 |
| 重跑 CI / 装新 IPA | 只有改了客户端推送代码才需要；**只配极光密钥不必重编** |

### ① Apple Developer（一次性）

1. [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles  
2. Identifiers → App ID **`com.liner0211.truckledger`** → 勾选 **Push Notifications**  
3. Keys → 新建 **Apple Push Notifications service (APNs)** Key，下载 `.p8`，记下 **Key ID**、**Team ID**  
   （也可用旧版 APNs 证书，极光两种都支持；推荐 `.p8`）

> CI 产出的是**未签名** IPA。你用爱思/巨魔/企业签等**重签安装**时，描述文件必须带 **Push**，否则极光拿不到 device token，后台仍无通知。

### ② 极光控制台

1. [jiguang.cn](https://www.jiguang.cn/) 建应用  
2. Android：包名 `com.liner0211.truckledger`  
3. iOS：Bundle ID `com.liner0211.truckledger`  
4. iOS 配置里上传 APNs：**Auth Key (.p8)** + Key ID + Team ID（或上传证书）  
5. 记下 **AppKey**、**Master Secret**

### ③ 生产服务器（必做，与 CI 无关）

SSH 编辑 `/www/wwwroot/truck.liner0211.online/config.php`（路径以你的 `SERVER_PATH` 为准）：

```php
'jpush_app_key' => '你的AppKey',
'jpush_master_secret' => '你的MasterSecret',
// CI / 正式重签安装的包 → true；仅 Xcode 调试包 → false
'jpush_apns_production' => true,
```

自检：

```bash
curl -fsS 'https://truck.liner0211.online/api/health?deep=1'
# 期望 checks.push = configured，detail 含 jpush
```

服务端诊断：

```bash
cd /www/wwwroot/truck.liner0211.online && php bin/test_jpush.php <用户id>
```

### ④ GitHub Actions（可选，主要利 Android）

仓库 Settings → Secrets：

| Secret | 用途 |
|--------|------|
| `JPUSH_APPKEY` | Release APK 写入 AndroidManifest；**建议与服务器 AppKey 相同** |

iOS CI **不读**这个 Secret；客户端用服务端下发的 key 调 `JPush.setup`。

### ⑤ 用户侧验证

1. 装当前云端 IPA（或等下次 CI）→ **重新登录**一次  
2. 库表 `push_tokens` 应出现 `jpush:……`  
3. App 退到后台 / 杀进程 → 管理端发站内信或跑 `test_jpush.php` → 应出系统通知  

---

## 行为说明

- **前台**：软件内横幅  
- **Android 后台（进程还在）**：本地通知栏（WS）  
- **iOS 后台 / 杀进程**：只能靠极光 → APNs  

详见 [`MESSAGING.md`](MESSAGING.md)。
