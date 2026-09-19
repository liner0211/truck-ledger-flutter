# 迁移配置清单（代码 / 服务器 / CI）

迁仓库、换开发机、换生产服务器时，**只对照本文 + [`dev/machine.env.example`](../dev/machine.env.example)**。  
本机密钥写在 `dev/machine.env`（gitignore）；GitHub Secrets 与远端 `config.php` **不要**写进 git。

相关：[`CI_AUTO_RELEASE.md`](CI_AUTO_RELEASE.md)、[`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md)、[`server-php/DEPLOY_truck.liner0211.online.md`](../server-php/DEPLOY_truck.liner0211.online.md)。

---

## 1. 本机脚本配置（`dev/machine.env`）

| 变量 | 用途 | 迁移 |
|------|------|------|
| `GITHUB_REPO` | `owner/repo`；空则从 `git remote` 推断 | 可选 |
| `PUBLIC_BASE_URL` | 拉 `downloads/truckledger-latest.*`、健康检查基址 | 迁域名必改 |
| `FLUTTER_BIN_PATH` | 本机 Flutter `bin` 目录（仅 debug） | 新机器必填 |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` / `GIT_REMOTE_URL` | `./dev/apply_git_config.sh` | 可选 |
| `DEVICE_USER` / `DEVICE_PASS` / `SUDO_PASS` / `DEVICE_IP` | 越狱 SSH 装 deb | 装 iOS 必填密码 |
| `ANDROID_IP` / `ANDROID_ADB_PORT` / `ANDROID_SERIAL` | adb 装 APK | 可选（可自动发现） |
| `SERVER_HOST` / `SERVER_USER` / `SERVER_PORT` / `SERVER_PATH` | 本机 `./one_click_server_deploy.sh` | 迁服务器必改 |
| `SERVER_SSH_KEY` | 本机 rsync 用私钥路径或内容 | 可选（也可用 ssh-agent） |
| `SERVER_HEALTH_URL` | 部署后健康检查 | 建议填 |

**工具依赖：** `git`、`gh auth login`、`curl`、`rsync`/`ssh`；deb 需 `python3`+`paramiko`；APK 需 `adb`。

**加载顺序：** `scripts/project_env.sh` → `dev/machine.env` → 可选 `.device.env`（后者覆盖）。

---

## 2. GitHub Secrets（仓库 Settings → Secrets）

| Secret | 用途 | 迁移 |
|--------|------|------|
| `ANDROID_KEYSTORE_BASE64` | Release APK 签名 | 正式签必填（缺则 debug 签） |
| `ANDROID_KEY_ALIAS` | 通常 `upload` | 同上 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 | 同上 |
| `ANDROID_KEY_PASSWORD` | key 密码 | 同上 |
| `SERVER_SSH_KEY` | CI 部署 / 上传 downloads | 迁服务器必换 |
| `SERVER_HOST` | SSH 主机 | 必换 |
| `SERVER_USER` | 默认 `root` | 按需 |
| `SERVER_PORT` | 默认 `22` | 按需 |
| `SERVER_PATH` | 站点根，默认 `/www/wwwroot/<域名>` | 必换 |
| `SERVER_HEALTH_URL` | Deploy 后检查 | 建议 |
| `PUBLIC_BASE_URL` | 控制面下载 URL 前缀（App + Admin CI） | 迁域名必换 |
| `CI_PUBLISH_TOKEN` | `POST /api/ci/publish-*`；须 = 远端 `config.php` 的 `ci_publish_token` | 必填且两边一致 |
| `FORCE_UPDATE_ON_RELEASE` | 可选 `1` 强更 | 可选 |

> 旧名 `SERVER_PUBLIC_BASE`（仅管理端）已兼容回退；新环境只配 **`PUBLIC_BASE_URL`**。

---

## 3. CI 工作流（自动编译 / 部署 / 上传）

| 工作流 | 触发 | 做什么 |
|--------|------|--------|
| **Release Packages** | push `main` 改 `lib/`、`shared/`、`android/`、`ios/`、`pubspec*` 等；或手动 | 编 APK/IPA/DEB → GitHub Release → scp `public/downloads/` → 控制面 `publish-release` |
| **Deploy Server PHP** | push 改 `server-php/**`；或手动 | rsync（保留 `config.php` / `data/` / `downloads/`） |
| **Release Admin Packages** | push 改 `admin_app/**`；或手动 | 管理端多平台包 → Release + downloads + admin 控制面 |
| Android APK Release / iOS Runner.app Build | **仅手动** | 与统一发版重叠，日常可忽略 |

本机总控：`./one_click_ship.sh`（push → 等上述 CI → 可选装包；有 `server-php` 时可本机并行 rsync）。

**约定：** 禁止本机 `flutter build` 出发布包。

---

## 4. 服务端（迁服务器）

| 项 | 说明 |
|----|------|
| 站点根 | 如 `/www/wwwroot/<域名>`；Web root = `public/` |
| `config.php` | 从 `server-php/config.example.php` 复制；**勿覆盖迁数据** |
| `jwt_secret` | ≥32 随机 |
| `ci_publish_token` | = GitHub `CI_PUBLISH_TOKEN` |
| `admin_*` | 首迁超级管理员 |
| `max_upload_bytes` | 与 nginx `client_max_body_size`（建议 ≥25m）一致 |
| 保留目录 | `data/`、`data/attachments/`、`public/downloads/` |
| Nginx | 参考 `server-php/nginx.*.conf`；`/api/`、`/admin/` → `index.php` |
| SSL | 宝塔或自备证书 |
| 健康检查 | `GET /api/health?deep=1` |
| Downloads | `truckledger-latest.{apk,ipa,deb}`；管理端 `truckledger-admin-latest.*` |

---

## 5. Android 签名

| 位置 | 说明 |
|------|------|
| 本机 | `android/key.properties` + `android/keystore/*.jks`（gitignore） |
| CI | Secrets 四件套写出 jks |
| 管理端 | 与主 App **共用**同一套 |

说明见 `android/SIGNING.md`。iOS CI 为 `--no-codesign`；越狱靠 deb。

---

## 6. App 内置云端域名（迁域名必改代码）

Release 不展示可编辑服务器地址，默认写死在：

- [`lib/state/auth_controller.dart`](../lib/state/auth_controller.dart) → `defaultServerUrl`
- [`admin_app/lib/admin_api.dart`](../admin_app/lib/admin_api.dart) → 默认 base URL

改完必须 **重新发版**（`./one_click_ship.sh`）。

---

## 7. 一键命令速查

```bash
cp dev/machine.env.example dev/machine.env   # 填配置
./one_click_ship.sh                         # 发版总控
./one_click_ship.sh --install-apk           # 发版后装 APK
./one_click_server_deploy.sh                # 仅部署 PHP
./one_click_apk_install.sh                  # 仅装 APK
./one_click_deb_install.sh                  # 仅装越狱 deb
./one_click_ipa.sh                          # 仅拉 IPA
```

---

## Checklist：新开发机

1. 克隆仓库；`cp dev/machine.env.example dev/machine.env` 并填写  
2. `gh auth login`；可选 `./dev/apply_git_config.sh`  
3. `flutter pub get`（`FLUTTER_BIN_PATH`）  
4. 越狱/Android 按需填 `DEVICE_*` / adb  
5. 本机装包：`./one_click_apk_install.sh` 等（依赖生产 downloads 或 Release）

## Checklist：只迁生产服务器

1. 新机装 PHP/Nginx/SSL；建站点根与 `public/`  
2. 部署代码：`./one_click_server_deploy.sh` 或 push 触发 Deploy  
3. 写入新 `config.php`（新 `jwt_secret`、与 GitHub 一致的 `ci_publish_token`）  
4. **保留或迁移** `data/`、`downloads/`  
5. 更新 GitHub Secrets：`SERVER_*`、`PUBLIC_BASE_URL`、`SERVER_HEALTH_URL`  
6. 更新本机 `machine.env` 同名字段  
7. 改 App/Admin `defaultServerUrl` 并 `./one_click_ship.sh` 发版  
8. 验证 `/api/health?deep=1` 与 downloads URL
