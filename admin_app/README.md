# 卡车记账 · 管理端（Flutter）

Android / iOS / Windows / Linux，对接 `/api/admin/*`。

**发布包一律由 CI 编译**（workflow：`Release Admin Packages`），勿在本机打正式包。

## 开发运行

```bash
cd admin_app
flutter pub get
flutter run -d linux          # 或 windows / android / ios
```

Release 默认服务器：`https://truck.liner0211.online`  
Debug 可在登录页改服务器地址。

## CI 产物

push `admin_app/**` 到 `main` 或手动 `workflow_dispatch` 后：

| 平台 | 产物 | 生产下载（示例） |
|------|------|------------------|
| Android | APK | `/downloads/truckledger-admin-latest.apk` |
| iOS | IPA（未签名） | `/downloads/truckledger-admin-latest.ipa` |
| Linux | tar.gz | `/downloads/truckledger-admin-latest-linux-x64.tar.gz` |
| Windows | zip | `/downloads/truckledger-admin-latest-windows-x64.zip` |

同时写入 GitHub Releases（tag 形如 `admin-v1.0.0-12`）。

## 权限

- **super**：控制面、删用户、运营账号管理
- **operator**：用户运营、消息

首次 Web/API 登录会从 `config.php` 的 `admin_username` + 密码种子超级管理员。
