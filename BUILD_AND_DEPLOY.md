# 卡车记账 Flutter — 云端发版与部署

本文档是**日常「怎么做」的权威源**：CI 发版、生产 downloads、控制面更新、PHP 部署。  
迁机 / Secrets 见 [`docs/MIGRATION.md`](./docs/MIGRATION.md)；CI 细节见 [`docs/CI_AUTO_RELEASE.md`](./docs/CI_AUTO_RELEASE.md)。

**硬约定：**

1. 发布包只在 GitHub Actions 中编译；本机禁止 `flutter build` / 直接跑 `package_*.sh` 出正式包。
2. 客户端安装与升级走**云端更新**（控制面 + `public/downloads/`）；仓库**不再提供**本机 adb / 越狱 SSH 装包脚本。

---

## 1. 项目是什么

| 项 | 说明 |
|----|------|
| 用途 | 车队记账：圈次、路线、费用、垫付、分成等 |
| 包名 | `com.liner0211.truckledger` |
| 数据 | 本地 JSON + 附件；可选云同步 |
| iOS 主交付 | **IPA**（应用内更新）；CI 仍可产出可选 **DEB** |
| 发版总控 | **`./one_click_ship.sh`** |
| 后端部署 | **`./one_click_server_deploy.sh`** 或 CI Deploy |

---

## 2. 新机器 Checklist

- [ ] 克隆仓库；`cp dev/machine.env.example dev/machine.env`
- [ ] 填 `FLUTTER_BIN_PATH`（本地 `flutter run`）；可选 `GITHUB_REPO` / `PUBLIC_BASE_URL` / `SERVER_*` / `GIT_*`
- [ ] `gh auth login`；可选 `./dev/apply_git_config.sh`
- [ ] `flutter pub get`；开发用 `flutter run`（Debug）
- [ ] 发版：`./one_click_ship.sh`（push → 等 CI → downloads / 控制面更新）
- [ ] 改后端：配好 `SERVER_*` 后 `./one_click_server_deploy.sh`，或 push `server-php/**`

字段说明见 [`docs/MIGRATION.md`](./docs/MIGRATION.md)。

---

## 3. 本机配置（勿提交密钥）

| 文件 | 作用 |
|------|------|
| **`dev/machine.env`** | GitHub / Flutter / `SERVER_*`；`scripts/project_env.sh` 加载 |
| **`.device.env`** | 可选覆盖 |

VS Code 任务见 **`.vscode/tasks.json`**（发版总控、部署 PHP、应用 Git 配置）。

---

## 4. 一键发版总控

```bash
./one_click_ship.sh -m "说明"
./one_click_ship.sh --keep-private     # 等 CI 时不临时公开仓库
make ship
```

流程：可选 commit →（默认临时 public）→ `git push` → 等 **Release Packages** / Deploy / Admin → 改回 private。有 `server-php` 变更时可本机并行 rsync。

成功后客户端从控制面拉取新版本；运维可核对：

- `{PUBLIC_BASE_URL}/downloads/truckledger-latest.{apk,ipa,deb}`
- `{PUBLIC_BASE_URL}/api/health?deep=1`

---

## 5. iOS / Android 产物（仅 CI）

- Android APK、iOS IPA（主更新包）、可选越狱 DEB：`.github/workflows/release-packages.yml`
- iOS：`scripts/flutter_build_ios_release.sh` + `package_ipa.sh`（+ 可选 `package_deb.sh`）
- 手动单平台 workflow 仅 `workflow_dispatch`，日常可忽略
- 管理端：`Release Admin Packages`

---

## 6. 后端部署

```bash
./one_click_server_deploy.sh
make server-deploy
```

保留远端 `config.php`、`data/`、`downloads/`。逐步说明见 [`server-php/DEPLOY_truck.liner0211.online.md`](./server-php/DEPLOY_truck.liner0211.online.md)。

---

## 7. 版本号

- 营销版本：`pubspec.yaml` 的 `version:` 前半段
- 构建号：CI 经 `scripts/flutter_build_version_env.sh`（`GITHUB_RUN_NUMBER`）注入
- 关于页：`package_info_plus`

---

## 8. 常见问题

| 现象 | 处理方向 |
|------|----------|
| App 仍提示旧版本 | 确认 **Release Packages** 成功且控制面 `latest_version` 已写回 |
| 生产 downloads 404 | 查 CI 上传步骤与 `PUBLIC_BASE_URL` |
| 本机跑 `package_*.sh` 报错 | 预期；请 `./one_click_ship.sh` |
| 后端未更新 | `./one_click_server_deploy.sh` 或等 Deploy Server PHP |

---

## 9. 相关文件

| 路径 | 说明 |
|------|------|
| `docs/CI_AUTO_RELEASE.md` | CI 与控制面 |
| `docs/MIGRATION.md` | Secrets / 迁服 |
| `one_click_ship.sh` / `one_click_server_deploy.sh` | 本机仅保留的运维入口 |
| `package_*.sh` / `scripts/flutter_build_*.sh` | **仅 CI** |
| `Makefile` | `ship` / `server-deploy` |
