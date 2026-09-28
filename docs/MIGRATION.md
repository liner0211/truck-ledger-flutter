# 迁移配置清单（代码 / 服务器 / CI）

迁仓库、换开发机、换生产服务器时，**只对照本文 + [`dev/machine.env.example`](../dev/machine.env.example)**。  
本机密钥写在 `dev/machine.env`（gitignore）；GitHub Secrets 与远端 `config.php` **不要**写进 git。

相关：[`CI_AUTO_RELEASE.md`](CI_AUTO_RELEASE.md)、[`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md)、[`server-php/DEPLOY_truck.liner0211.online.md`](../server-php/DEPLOY_truck.liner0211.online.md)。

---

## 1. 本机脚本配置（`dev/machine.env`）

| 变量 | 用途 | 迁移 |
|------|------|------|
| `GITHUB_REPO` | `owner/repo`；空则从 `git remote` 推断 | 可选 |
| `PUBLIC_BASE_URL` | downloads / 健康检查基址 | 迁域名必改 |
| `FLUTTER_BIN_PATH` | 本机 Flutter `bin`（仅 debug） | 新机器必填 |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` / `GIT_REMOTE_URL` | `./dev/apply_git_config.sh` | 可选 |
| `SERVER_HOST` / `SERVER_USER` / `SERVER_PORT` / `SERVER_PATH` | `./one_click_server_deploy.sh` | 迁服务器必改 |
| `SERVER_SSH_KEY` | 本机 rsync 用私钥路径或内容 | 可选（也可用 ssh-agent） |
| `SERVER_HEALTH_URL` | 部署后健康检查 | 建议填 |

**工具依赖：** `git`、`gh auth login`、`curl`、`rsync`/`ssh`（部署后端时）。

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
| `PUBLIC_BASE_URL` | 控制面下载 URL 前缀 | 迁域名必换 |
| `CI_PUBLISH_TOKEN` | `POST /api/ci/publish-*`；须 = 远端 `ci_publish_token` | 必填且两边一致 |
| `FORCE_UPDATE_ON_RELEASE` | 可选 `1` 强更 | 可选 |
| `JPUSH_APPKEY` | 可选；Release 注入 Android manifest 极光 AppKey | 杀进程推送建议填 |

> 旧名 `SERVER_PUBLIC_BASE`（仅管理端）已兼容回退；新环境只配 **`PUBLIC_BASE_URL`**。

---

## 3. CI 工作流

| 工作流 | 触发 | 做什么 |
|--------|------|--------|
| **Release Packages** | push App 相关路径；或手动 | 编 APK/IPA/DEB → Release → downloads → 控制面 |
| **Deploy Server PHP** | push `server-php/**`；或手动 | rsync（保留 config/data/downloads） |
| **Release Admin Packages** | push `admin_app/**`；或手动 | 管理端多平台包 |
| Android APK / iOS Runner 手动 workflow | 仅手动 | 日常可忽略 |

本机总控：`./one_click_ship.sh`（push → 等 CI；有 `server-php` 时可本机并行 rsync）。客户端更新走控制面，无本机装包步骤。

**临时公开：** 默认等 CI 前改为 public，结束后改回 private；`--keep-private` 或 `SHIP_TEMP_PUBLIC=0` 关闭。

**约定：** 禁止本机 `flutter build` 出发布包。

---

## 4. 服务端（迁服务器）

| 项 | 说明 |
|----|------|
| 站点根 | 如 `/www/wwwroot/<域名>`；Web root = `public/` |
| `config.php` | 从 `config.example.php` 复制；**勿覆盖迁数据** |
| `jwt_secret` | ≥32 随机 |
| `ci_publish_token` | = GitHub `CI_PUBLISH_TOKEN` |
| `jpush_app_key` / `jpush_master_secret` | 国内杀进程推送（极光）；见 [`CN_PUSH.md`](CN_PUSH.md) |
| `admin_*` | 首迁超级管理员 |
| `max_upload_bytes` | 与 nginx `client_max_body_size`（建议 ≥25m）一致 |
| 保留目录 | `data/`、`attachments/`、`public/downloads/` |
| 健康检查 | `GET /api/health?deep=1` |
| Downloads | `truckledger-latest.{apk,ipa,deb}`；管理端 `truckledger-admin-latest.*` |

---

## 5. Android 签名

| 位置 | 说明 |
|------|------|
| 本机 | `android/key.properties` + `android/keystore/*.jks`（gitignore） |
| CI | Secrets 四件套 |
| 管理端 | 与主 App **共用**同一套 |

见 [`android/SIGNING.md`](../android/SIGNING.md)。iOS 见 [`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md) §5。

---

## 6. App 内置云端域名（迁域名必改代码）

- [`lib/state/auth_controller.dart`](../lib/state/auth_controller.dart) → `defaultServerUrl`
- [`admin_app/lib/admin_api.dart`](../admin_app/lib/admin_api.dart) → 默认 base URL

改完必须 **`./one_click_ship.sh` 重新发版**。

---

## 7. 一键命令速查

```bash
cp dev/machine.env.example dev/machine.env   # 填配置
./one_click_ship.sh                         # 云端发版总控
./one_click_server_deploy.sh                # 仅部署 PHP
```

---

## Checklist：新开发机

1. 克隆；`cp dev/machine.env.example dev/machine.env` 并填写  
2. `gh auth login`；可选 `./dev/apply_git_config.sh`  
3. `flutter pub get`（`FLUTTER_BIN_PATH`）  
4. 发版用 `./one_click_ship.sh`；装包/升级在 App 内云端更新

## Checklist：只迁生产服务器

1. 新机装 PHP/Nginx/SSL；建站点根与 `public/`  
2. `./one_click_server_deploy.sh` 或 push 触发 Deploy  
3. 写入新 `config.php`（新 `jwt_secret`、与 GitHub 一致的 `ci_publish_token`）  
4. **保留或迁移** `data/`、`downloads/`  
5. 更新 GitHub Secrets：`SERVER_*`、`PUBLIC_BASE_URL`、`SERVER_HEALTH_URL`  
6. 更新本机 `machine.env` 同名字段  
7. 改 App/Admin `defaultServerUrl` 并 `./one_click_ship.sh`  
8. 验证 `/api/health?deep=1` 与 downloads URL
