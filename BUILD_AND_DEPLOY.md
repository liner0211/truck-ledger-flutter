# 卡车记账 Flutter — 编译、打包与部署手册

本文档面向在新电脑 / 新环境中恢复开发，以及通过 **CI** 产出并安装 **Android APK**、**越狱 deb**、**IPA 容器** 的流程。

**硬约定：所有发布包只在 GitHub Actions 中编译；本机禁止用 `flutter build` / `package_*.sh` 产出正式安装包。** 本机一键脚本只负责下载 CI/生产产物并安装。

---

## 1. 项目是什么

| 项 | 说明 |
|----|------|
| 用途 | 车队记账：圈次、路线、费用、垫付、分成、Excel 导出等 |
| 包名 | `com.liner0211.truckledger`，桌面名「卡车记账」 |
| 数据 | 本地 JSON（`ledger_book.json` + `attachments/`） |
| iOS 越狱安装 | 安装到 `/Applications` 的 **deb**（非 App Store 流程） |
| 发版 | `docs/CI_AUTO_RELEASE.md` |

---

## 2. 新机器 Checklist

### 2.1 通用

- [ ] **Git**、克隆本仓库
- [ ] **`cp dev/machine.env.example dev/machine.env`**，填写 `DEVICE_PASS`、可选 `GITHUB_REPO` / `PUBLIC_BASE_URL` / `SERVER_*` / `GIT_*`
- [ ] 可选：`./dev/apply_git_config.sh`
- [ ] 开发调试：本机 **Flutter**（`flutter run` / Debug）；WSL 用 Linux 侧 SDK
- [ ] `flutter pub get`；阅读 [`AGENTS.md`](./AGENTS.md)

### 2.2 安装发布包（无需本机编 Release）

- [ ] **Android**：`adb` + `./one_click_apk_install.sh`（从生产 downloads 或 GitHub Release 拉 APK）
- [ ] **越狱 iOS**：`python3` + `paramiko` + `DEVICE_PASS` + `./one_click_deb_install.sh`
- [ ] **IPA 容器**：`./one_click_ipa.sh`（需可访问 GitHub Release；或 `gh auth login`）
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

所有 **`deploy.sh` / `debug.sh` / 一键脚本** 会加载上述配置。VS Code 任务经 **`./scripts/with_project_env.sh`**；任务里填的 `DEVICE_PASS` 可覆盖文件中的值。

### VS Code 一键任务

- **一键：Android 安装 CI APK 到设备**
- **一键：拉取 CI IPA**
- **一键：拉取 CI deb 并安装越狱机**
- **一键：部署 PHP 后端**

见 **`.vscode/tasks.json`**。

---

## 4. Android：安装（不本地编 Release）

```bash
./one_click_apk_install.sh
# 等价：从 https://…/downloads/truckledger-latest.apk 或最新 GitHub Release 下载后 adb install -r
```

开发联调仍可用 `flutter run`；**不要**用本机 `flutter build apk --release` 当正式发布包（签名与构建号以 CI 为准）。

---

## 5. iOS / 越狱：CI 产物

- 主流程：`.github/workflows/release-packages.yml`（APK + IPA + DEB + 上传 downloads + 控制面版本）
- 手动单平台仍可用：`iOS Runner.app Build` / `Android APK Release`（workflow_dispatch）
- 本机安装：

```bash
./one_click_ipa.sh              # → ipa-out/Runner.ipa
./one_click_deb_install.sh      # 拉 deb → deploy.sh
```

应用内更新：Android 用 APK，iOS 用 **IPA**（`ios_download_url` → `truckledger-latest.ipa`）。越狱 deb 仍可由 CI 产出，供 `./one_click_deb_install.sh`，不作为更新地址。

管理端改动走 **`Release Admin Packages`**（Android / iOS / Linux / Windows）。

---

## 6. 一键脚本一览

| 脚本 | 作用 |
|------|------|
| **`./one_click_ipa.sh`** | 拉 CI IPA → `ipa-out/Runner.ipa` |
| **`./one_click_deb_install.sh`** | 拉 CI deb → **`deploy.sh`** 安装 |
| **`./one_click_apk_install.sh`** | 拉 CI APK → **`adb install -r`** |
| **`./one_click_find_android.sh`** | 仅发现 Android 设备 |
| **`./one_click_server_deploy.sh`** | rsync `server-php/` |
| **`./scripts/fetch_ci_release_asset.sh`** | `apk` / `deb` / `ipa` 下载底层 |

```bash
make ipa-one
make deb-install-one
make apk-install-one
make server-deploy
```

已有 deb 仅安装：`DEB_FILE=packages/xxx.deb ./deploy.sh`（或 `packages/*.deb`）。

---

## 7. deb 与越狱机

- 版本与 CI 写入的 `pubspec` / 构建号一致。
- 闪退排查：`./debug.sh` + 设备日志。

---

## 8. 版本号与应用内展示

- **`pubspec.yaml`**：`version: x.y.z+…`（改营销版本改 `+` 前半段）
- 关于页：`package_info_plus`（CI 注入的 `--build-name` / `--build-number`）
- 自动构建号：`scripts/flutter_build_version_env.sh`（CI 用 `GITHUB_RUN_NUMBER`）

---

## 9. ETC 对账手续费

- `lib/services/profit_calculator.dart`：`etcTollReconcileRate = 0.0035`（**0.35%**）

---

## 10. 常见问题

| 现象 | 处理方向 |
|------|----------|
| **改代码后一键仍是旧包** | 需 **push** 且 **Release Packages** 成功，生产 downloads / Release 已更新后再跑一键 |
| 生产下载失败 | 配置 `gh auth login`，脚本会回退 GitHub Release |
| `deploy.sh` 要 `DEVICE_PASS` | 写 `dev/machine.env` |
| SSH `Connection refused` | 核对手机 IP / 越狱 SSH；可清空错误的 `DEVICE_IP` 让脚本扫描 |
| 本机跑 `package_deb.sh` 报错 | 预期行为；请用一键拉 CI 包 |

---

## 11. 相关文件索引

| 路径 | 说明 |
|------|------|
| `docs/CI_AUTO_RELEASE.md` | CI 发版与控制面 |
| `scripts/fetch_ci_release_asset.sh` | 拉取 apk/deb/ipa |
| `deploy.sh` | 安装已有 deb（不编译） |
| `debug.sh` | SSH 调试 |
| `package_deb.sh` / `package_ipa.sh` | **仅 CI** 组装 |
| `scripts/flutter_build_ios_release.sh` | **仅 CI** iOS build |
| `scripts/flutter_build_version_env.sh` | CI 构建号 |
| `.vscode/tasks.json` | 一键任务 |
| `Makefile` | `ipa-one` / `deb-install-one` / `apk-install-one` / `server-deploy` |

---

如有流程变更，优先更新本文档与 `.github/workflows`，并保持「发布只走 CI」。
