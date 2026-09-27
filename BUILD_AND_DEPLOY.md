# 卡车记账 Flutter — 编译、打包与部署手册

本文档是**日常「怎么做」的权威源**：新环境恢复、一键发版、装包。  
迁机 / Secrets / 换服对照表见 [`docs/MIGRATION.md`](./docs/MIGRATION.md)；CI 触发与控制面回写见 [`docs/CI_AUTO_RELEASE.md`](./docs/CI_AUTO_RELEASE.md)。

**硬约定：所有发布包只在 GitHub Actions 中编译；本机禁止用 `flutter build` / `package_*.sh` 产出正式安装包。** 本机一键脚本只负责下载 CI/生产产物并安装。

---

## 1. 项目是什么

| 项 | 说明 |
|----|------|
| 用途 | 车队记账：圈次、路线、费用、垫付、分成、Excel 导出等 |
| 包名 | `com.liner0211.truckledger`，桌面名「卡车记账」 |
| 数据 | 本地 JSON（`ledger_book.json` + `attachments/`） |
| iOS 主交付 | **IPA**（应用内更新）；可选 **DEB** 越狱装到 `/Applications` |
| 发版总控 | **`./one_click_ship.sh`** |
| 迁移配置 | [`docs/MIGRATION.md`](./docs/MIGRATION.md) |

---

## 2. 新机器 Checklist

### 2.1 通用

- [ ] **Git**、克隆本仓库
- [ ] **`cp dev/machine.env.example dev/machine.env`**，填写 `DEVICE_PASS`、可选 `GITHUB_REPO` / `PUBLIC_BASE_URL` / `SERVER_*` / `GIT_*`（字段说明见 MIGRATION）
- [ ] 可选：`./dev/apply_git_config.sh`
- [ ] 开发调试：本机 **Flutter**（`flutter run` / Debug）；WSL 用 Linux 侧 SDK
- [ ] `flutter pub get`；阅读 [`AGENTS.md`](./AGENTS.md)

### 2.2 安装发布包（无需本机编 Release）

- [ ] **Android**：`adb` + `./one_click_apk_install.sh`
- [ ] **IPA**：`./one_click_ipa.sh`
- [ ] **越狱 DEB**（可选）：`python3` + `paramiko` + `DEVICE_PASS` + `./one_click_deb_install.sh`
- [ ] 发版前：代码 **push `main`**，等 **Release Packages** 成功（或确认生产 `/downloads/` 已更新）

### 2.3 仅运维 / 改后端

- [ ] `SERVER_*` 配好后 `./one_click_server_deploy.sh`；或依赖 push `server-php/**` 触发的 Deploy Server PHP

---

## 3. 本地文件约定（勿提交密钥）

| 文件 | 作用 |
|------|------|
| **`dev/machine.env`** | 本机配置；`scripts/project_env.sh` 自动加载 |
| **`.device.env`** | 可选覆盖 |
| **`.last_device_ip`** | 上次成功 IP 缓存 |

所有 **`deploy.sh` / `debug.sh` / 一键脚本** 会加载上述配置。VS Code 任务经 **`./scripts/with_project_env.sh`**。

见 **`.vscode/tasks.json`**：「一键：…」系列。

---

## 4. 一键发版总控

```bash
./one_click_ship.sh -m "说明"          # 有未提交改动时自动 commit
./one_click_ship.sh --install-apk      # CI 成功后 adb 安装
./one_click_ship.sh --keep-private     # 等 CI 时不临时公开仓库
make ship
```

流程：可选 commit →（默认临时 public）→ `git push` → 等 **Release Packages** / 相关 workflow → 改回 private → 可选装包；有 `server-php` 变更时可本机 rsync。

CI 细节（downloads 名、控制面 API）→ [`docs/CI_AUTO_RELEASE.md`](./docs/CI_AUTO_RELEASE.md)。  
GitHub Secrets 全表 → [`docs/MIGRATION.md`](./docs/MIGRATION.md) §2。

---

## 5. Android：安装（不本地编 Release）

```bash
./one_click_apk_install.sh
```

开发联调仍可用 `flutter run`；**不要**用本机 `flutter build apk --release` 当正式发布包。

手动单平台 workflow：`Android APK Release`（仅 `workflow_dispatch`；日常用 Release Packages）。

---

## 6. iOS：CI 产物

标准 Flutter 工程 `ios/Runner.xcodeproj`：CI 跑 `flutter build ios --release --no-codesign`（`scripts/flutter_build_ios_release.sh`）。不在本机编 Release。

- 主交付：**IPA**（`package_ipa.sh`，应用内更新 `ios_download_url`）
- 可选：**DEB**（`package_deb.sh` / `dpkg-deb`，越狱）
- 主流程：`.github/workflows/release-packages.yml`
- 手动单平台：`iOS Runner.app Build`（日常可忽略）

```bash
./one_click_ipa.sh              # → ipa-out/Runner.ipa
./one_click_deb_install.sh      # 拉 deb → deploy.sh
```

管理端改动走 **`Release Admin Packages`**。

---

## 7. 一键脚本一览

| 脚本 | 作用 |
|------|------|
| **`./one_click_ship.sh`** | **总控**：push → 等 CI → 可选装包 |
| `./one_click_ipa.sh` | 拉 CI/生产 IPA → `ipa-out/Runner.ipa` |
| `./one_click_deb_install.sh` | 拉 deb → **`deploy.sh`** |
| `./one_click_apk_install.sh` | 拉 APK → **`adb install -r`** |
| `./one_click_find_android.sh` | 仅发现 Android 设备 |
| `./one_click_server_deploy.sh` | rsync `server-php/` |
| `./scripts/fetch_ci_release_asset.sh` | 下载底层 |

```bash
make ship
make ipa-one
make deb-install-one
make apk-install-one
make server-deploy
```

已有 deb 仅安装：`DEB_FILE=packages/xxx.deb ./deploy.sh`。

---

## 8. deb 与越狱机

- 版本与 CI 构建号一致。
- 闪退排查：`./debug.sh` + 设备日志。

---

## 9. 版本号与应用内展示

- **`pubspec.yaml`**：`version: x.y.z+…`（改营销版本改 `+` 前半段）
- 关于页：`package_info_plus`（CI 注入的 `--build-name` / `--build-number`）
- 自动构建号：`scripts/flutter_build_version_env.sh`（CI 用 `GITHUB_RUN_NUMBER`）

---

## 10. ETC 对账手续费

- `lib/services/profit_calculator.dart`：`etcTollReconcileRate = 0.0035`（**0.35%**）

---

## 11. 常见问题

| 现象 | 处理方向 |
|------|----------|
| **改代码后一键仍是旧包** | 需 **push** 且 **Release Packages** 成功后再跑一键 |
| 生产下载失败 | `gh auth login`，脚本回退 GitHub Release |
| `deploy.sh` 要 `DEVICE_PASS` | 写 `dev/machine.env` |
| SSH `Connection refused` | 核对手机 IP / 越狱 SSH |
| 本机跑 `package_deb.sh` 报错 | 预期；请用一键拉 CI 包 |

---

## 12. 相关文件索引

| 路径 | 说明 |
|------|------|
| `docs/CI_AUTO_RELEASE.md` | CI 发版与控制面 |
| `docs/MIGRATION.md` | Secrets / 迁服 |
| `scripts/fetch_ci_release_asset.sh` | 拉取 apk/deb/ipa |
| `deploy.sh` / `debug.sh` | 装 deb / SSH 调试 |
| `package_deb.sh` / `package_ipa.sh` | **仅 CI** 组装 |
| `scripts/flutter_build_ios_release.sh` | **仅 CI** iOS build |
| `.vscode/tasks.json` | 一键任务 |
| `Makefile` | `ship` / `ipa-one` / … |

如有流程变更，优先更新本文档与 `.github/workflows`，并保持「发布只走 CI」。
