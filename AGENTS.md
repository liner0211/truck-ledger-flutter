# 给 AI 助手 / 新对话的快速上下文

接手本项目时：先读 **[`BUILD_AND_DEPLOY.md`](BUILD_AND_DEPLOY.md)**（怎么做），再读本文件（约束与索引）。  
迁机 / 迁服 / Secrets：[`docs/MIGRATION.md`](docs/MIGRATION.md)（模板 `dev/machine.env.example`）。

## 项目目的

Flutter「卡车记账」，包名 `com.liner0211.truckledger`，版本见 `pubspec.yaml`。本地 JSON + 附件；后端 **`server-php/`**。iOS 为标准 `ios/` + CI `flutter build ios`：**IPA** 主交付，可选 DEB（CI 组装）。客户端安装/升级走**云端更新**，无本机装包脚本。

## AI 协作约定

- 功能/修复完成后优先 **`./one_click_ship.sh`**（可 `-m "说明"`；已 commit 则 push → **有路径触发才等 CI** → 有 `server-php` 变更则本机 rsync）。
- **无新代码改动 / 路径不触发发版 workflow 时不重跑 CI**；确需重跑加 `--force-ci`。
- 等 CI 时默认临时公开仓库、结束后改回私有；不需要时加 `--keep-private`。
- 例外：改动含密钥、破坏性操作、或用户明确只要本地改时，先停并说明。

## 发行版产品约定（重要）

- Release：**不展示、不编辑** API 域名；错误文案只说「云服务 / 网络」。
- Debug / Profile：可显示「服务器地址（仅调试）」。
- 域名与部署只写运维文档，**不要**写进司机 UI。

## 配置

- **`dev/machine.env`**（gitignore）：由 `scripts/project_env.sh` 加载（GitHub / Flutter / `SERVER_*`）。
- **`.device.env`**：若存在，在其后加载并覆盖。

云端发版与部署 → **[`BUILD_AND_DEPLOY.md`](BUILD_AND_DEPLOY.md)**。  
Secrets / 换服 → **[`docs/MIGRATION.md`](docs/MIGRATION.md)**。  
CI 触发与 downloads → **[`docs/CI_AUTO_RELEASE.md`](docs/CI_AUTO_RELEASE.md)**。

**约定：** 发布包只由 CI 编译并上传；本机可 `flutter run` 调试，禁止本机编 Release。

## 关键文件

| 路径 | 说明 |
|------|------|
| `BUILD_AND_DEPLOY.md` | 云端发版 / 部署权威 |
| `docs/MIGRATION.md` | 迁机 / Secrets / 换服 |
| `docs/CI_AUTO_RELEASE.md` | CI 与控制面回写 |
| `docs/MESSAGING.md` | 站内通知 / 已读 / 强制删 / 客服会话 |
| `dev/machine.env.example` | 本机配置模板 |
| `one_click_ship.sh` | 发版总控 |
| `one_click_server_deploy.sh` | rsync `server-php/` |
| `package_deb.sh` / `package_ipa.sh` | **仅 CI** 组装 |
| `scripts/flutter_build_*.sh` | **仅 CI** 构建号 / iOS |
| `.github/workflows/release-packages.yml` | 统一发版 |
| `lib/state/auth_controller.dart` | 内置默认云端 URL |

## 业务常量

- ETC 对账手续费：**0.35%**（`etcTollReconcileRate = 0.0035`）。

## 云端能力（摘要）

控制面、`revision` 同步与冲突、试用/到期、站内信、极光推送、功能开关。详情见 [`server-php/README.md`](server-php/README.md)。部署：`./one_click_server_deploy.sh`；App CI：`Release Packages`；管理端：`Release Admin Packages`。

## 版本号

- 关于页：`package_info_plus`（CI 注入构建号）。
- 营销版本改 `pubspec.yaml` 的 `version:` 行。

## 备份

导出 ZIP / 导入 `.zip`·`.json`（合并或覆盖）。实现：`ledger_backup_*.dart`。

## 不要提交

`dev/machine.env`、`.device.env`、密钥、PAT、私钥、`packages/`、`ipa-out/`、`android/build/`（见 `.gitignore`）。
