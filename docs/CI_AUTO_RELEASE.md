# CI 自动部署与版本推送

Secrets 全表见 [`MIGRATION.md`](MIGRATION.md)。日常发版见 [`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md)。

## 流程

1. **push `main` 且改 `server-php/`** → `Deploy Server PHP`：rsync（保留 `config.php` / `data/` / `public/downloads/`）
2. **push `main` 且改 App** → `Release Packages`：编 APK/IPA + 可选 DEB → Release → `public/downloads/` → `/api/ci/publish-release`（**`ios_download_url` 指向 IPA**）
3. **push `main` 且改 `admin_app/**`** → `Release Admin Packages` → `downloads/truckledger-admin-latest.*`

控制面 `latest_version` 写成 **`营销版本+构建号`**（如 `1.2.0+45`）。`FORCE_UPDATE_ON_RELEASE=1` 时可强更。

同步内容：

- `public/downloads/truckledger-latest.{apk,ipa,deb}`
- `/api/ci/publish-release` → `latest_version` / `apk_download_url` / `ios_download_url`（IPA）

管理端：Release `admin-v*`，并挂到主 App Latest `v*`。

客户端通过控制面检查更新并下载，无需本机装包脚本。

## 远端 config.php 必填

```php
'ci_publish_token' => '长随机串',
```

须与 GitHub Secret `CI_PUBLISH_TOKEN` 一致（见 [MIGRATION.md](MIGRATION.md) §2；签名见 [`android/SIGNING.md`](../android/SIGNING.md)）。

## 本机运维入口

```bash
./one_click_ship.sh             # 发版总控（push → 等 CI）
./one_click_server_deploy.sh    # 部署 PHP
```
