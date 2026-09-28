# 国内系统通知（Android / iOS）

国内手机通常**没有 Google Play 服务**，本项目不使用 FCM，采用：

| 通道 | 作用 |
|------|------|
| WebSocket + **本地通知栏** | App 进程在线时收到消息 → 通知栏 |
| **极光 JPush** | 杀进程 / **iOS 后台**仍能推到通知栏（必须配置） |

> 生产健康检查若 `checks.push=optional`：远端尚未填极光 → **iOS 后台一定无系统通知**。

---

## CI 编 IPA + 自签安装后要有后台推送

本仓库 CI：`flutter build ios --release --no-codesign` → 打成 IPA。  
AppKey **不写死在 IPA 里**，登录后由服务器 `/api/app/check` 下发。

### 硬性前提（缺一不可）

1. **付费 Apple Developer（年费）**  
   免费 Apple ID / 仅爱思免费签 **不能**开 Push，APNs 拿不到 token，后台通知做不到。  
2. App ID `com.liner0211.truckledger` 勾选 **Push Notifications**  
3. 极光控制台上传 APNs（`.p8` 推荐）+ 服务器填 `jpush_*`  
4. **重签时必须带上 Push entitlement**（工程已含 `ios/Runner/Runner.entitlements`，`aps-environment=production`）

### ① Apple + 极光（网页）

1. Identifiers → `com.liner0211.truckledger` → Push Notifications  
2. Keys → APNs Key → 下 `.p8`，记 Key ID、Team ID  
3. [极光](https://www.jiguang.cn/) 建应用，iOS Bundle Id 同上，上传 APNs  
4. 记下 **AppKey**、**Master Secret**

### ② 服务器（与 CI 无关，SSH 改 `config.php`）

```php
'jpush_app_key' => '你的AppKey',
'jpush_master_secret' => '你的MasterSecret',
// 自签若用「Apple Development」证书 → false，且 entitlements 改为 development
// CI/企业签/Ad Hoc/正式 → true（与仓库 Runner.entitlements 默认 production 一致）
'jpush_apns_production' => true,
```

自检：`curl -fsS 'https://你的域名/api/health?deep=1'` → `checks.push=configured`

### ③ 自签重签时带上 Push（关键）

CI 包旁会附带 `Runner.entitlements`。重签示例：

```bash
# 用带 Push 的描述文件 / 证书重签（工具因人而异，核心是 entitlements）
codesign -f -s "Apple Distribution: Your Name (TEAMID)" \
  --entitlements Runner.entitlements \
  Payload/Runner.app
```

| 工具 | 注意 |
|------|------|
| 爱思助手 / Sideloadly | 选**付费开发者账号**；确认能力含 Push |
| 企业签 / TF | 描述文件勾选 Push |
| 免费七天签 | **无法**后台推送 |

若你实际用的是 **Development** 证书自签：把 `Runner.entitlements` 里 `aps-environment` 改成 `development`，服务器 `jpush_apns_production` 改 `false`，再编一版 IPA。

### ④ GitHub Secret（可选，Android）

| Secret | 用途 |
|--------|------|
| `JPUSH_APPKEY` | 写入 AndroidManifest；建议与服务器 AppKey 相同 |

iOS CI **不读**该 Secret。

### ⑤ 验证

1. 重签安装 → **重新登录**  
2. 库表 `push_tokens` 有 `jpush:…`  
3. 杀进程后 `php bin/test_jpush.php <user_id>` 或管理端发信 → 应出系统通知  

---

## 行为说明

- **前台**：软件内横幅  
- **Android 后台（进程还在）**：本地通知栏（WS）  
- **iOS 后台 / 杀进程**：只能靠极光 → APNs  

详见 [`MESSAGING.md`](MESSAGING.md)。
