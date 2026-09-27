# CI 自动部署与版本推送

Secrets 全表与迁服对照见 [`MIGRATION.md`](MIGRATION.md)。日常装包见 [`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md)。

## 流程

1. **push `main` 且改 `server-php/`** → `Deploy Server PHP`：rsync 到宝塔（保留 `config.php` / `data/` / `public/downloads/`）
2. **push `main` 且改 App（lib/android/ios/pubspec 等）** → `Release Packages`：编 APK/IPA + 可选 DEB → GitHub Release → 上传到 `public/downloads/` → `/api/ci/publish-release`（**`ios_download_url` 指向 IPA**）
3. **push `main` 且改 `admin_app/**`** → `Release Admin Packages`：管理端多平台包 → Release + `downloads/truckledger-admin-latest.*`

控制面 `latest_version` 写成 **`营销版本+构建号`**（如 `1.2.0+45`），与 App 内 `version+buildNumber` 比较。若 `FORCE_UPDATE_ON_RELEASE=1` 则对低于最新版强制更新。

发版同步内容：

- `public/downloads/truckledger-latest.{apk,ipa,deb}`
- `/api/ci/publish-release` → `latest_version` / `apk_download_url` / `ios_download_url`（IPA）

管理端：独立 Release `admin-v*`，并挂到主 App Latest Release `v*`。

手动单平台（日常可忽略）：`Android APK Release` / `iOS Runner.app Build`（仅 `workflow_dispatch`）。

## 远端 config.php 必填

```php
'ci_publish_token' => '长随机串',
```

须与 GitHub Secret `CI_PUBLISH_TOKEN` **完全一致**（Secrets 见 [MIGRATION.md](MIGRATION.md) §2；Android 签名见 [`android/SIGNING.md`](../android/SIGNING.md)）。

## 本机安装（不编译）

```bash
./one_click_ship.sh             # 推荐总控
./one_click_apk_install.sh
./one_click_deb_install.sh
./one_click_ipa.sh
```

优先从 `PUBLIC_BASE_URL/downloads/truckledger-latest.{apk,ipa,deb}` 下载；失败则用 `gh` 拉最新 GitHub Release。

管理端产物见 [`admin_app/README.md`](../admin_app/README.md)。
