# CI 自动部署与版本推送

## 流程

1. **push `main` 且改 `server-php/`** → `Deploy Server PHP`：rsync 到宝塔（保留 `config.php` / `data/` / `public/downloads/`）
2. **push `main` 且改 App（lib/android/ios/pubspec）** → `Release Packages`：编 APK/IPA/DEB → GitHub Release → 上传 APK/**IPA**/DEB 到服务器 `public/downloads/` → 调用 `/api/ci/publish-release` 更新控制面（**`ios_download_url` 指向 IPA**，不再用 deb）
3. **push `main` 且改 `admin_app/**`** → `Release Admin Packages`：编管理端 Android / iOS / Linux / Windows → GitHub Release → 上传到 `downloads/truckledger-admin-latest.*`

客户端随后会在关于页/横幅看到新版本；控制面 `latest_version` 会写成 **`营销版本+构建号`**（如 `1.2.0+45`），与 App 内 `version+buildNumber` 比较，因此每次 CI 发版上传安装包时都会同步可更新提示。若 Secrets 中 `FORCE_UPDATE_ON_RELEASE=1` 则对低于最新版的用户强制更新。

发版同步内容：
- `public/downloads/truckledger-latest.{apk,ipa,deb}`
- `/api/ci/publish-release` → `latest_version` / `apk_download_url` / `ios_download_url`（IPA）/ 更新说明
- **GitHub Releases**：`Release Packages` / `Release Admin Packages` 以及手动 `Android APK Release` / `iOS Runner.app Build` 的安装包均挂到对应 Release

## 远端 config.php 必填

```php
'ci_publish_token' => '长随机串',
```

与 GitHub Secret `CI_PUBLISH_TOKEN` **完全一致**。

## GitHub Secrets

| Secret | 用途 |
|--------|------|
| `SERVER_SSH_KEY` | 部署/上传用私钥全文 |
| `SERVER_HOST` | 如 `truck.liner0211.online` |
| `SERVER_USER` | 默认 `root` |
| `SERVER_PORT` | 默认 `22` |
| `SERVER_PATH` | 默认 `/www/wwwroot/truck.liner0211.online` |
| `SERVER_HEALTH_URL` | 可选，健康检查 URL |
| `PUBLIC_BASE_URL` | 默认 `https://truck.liner0211.online` |
| `CI_PUBLISH_TOKEN` | 与 config `ci_publish_token` 相同 |
| `FORCE_UPDATE_ON_RELEASE` | 可选，`1` 则每次发版强制更新 |
| Android 签名四件套 | 见 `android/SIGNING.md` |

## 本机安装（不编译）

```bash
./one_click_apk_install.sh
./one_click_deb_install.sh
./one_click_ipa.sh
```

优先从 `PUBLIC_BASE_URL/downloads/truckledger-latest.{apk,ipa,deb}` 下载；失败则用 `gh` 拉最新 GitHub Release。

管理端产物：`truckledger-admin-latest.{apk,ipa}` 与 linux/windows 包，见 `admin_app/README.md`。
