# CI 自动部署与版本推送

## 流程

1. **push `main` 且改 `server-php/`** → `Deploy Server PHP`：rsync 到宝塔（保留 `config.php` / `data/` / `public/downloads/`）
2. **push `main` 且改 App（lib/android/ios/pubspec）** → `Release Packages`：编 APK/IPA/DEB → GitHub Release → 上传 APK/DEB 到服务器 `public/downloads/` → 调用 `/api/ci/publish-release` 更新控制面 `latest_version` 与下载地址

客户端随后会在关于页/横幅看到新版本；若 Secrets 中 `FORCE_UPDATE_ON_RELEASE=1` 则对低于最新版的用户强制更新。

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

## 下载地址示例

- APK：`https://truck.liner0211.online/downloads/truckledger-latest.apk`
- DEB：`https://truck.liner0211.online/downloads/truckledger-latest.deb`
