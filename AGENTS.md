# 给 AI 助手 / 新对话的快速上下文

在新 Cursor 窗口接手本项目时，先读 **`BUILD_AND_DEPLOY.md`**（全流程），再读本文件（索引）。

## 项目目的

Flutter 版「卡车记账」，包名 `com.liner0211.truckledger`，当前版本见 `pubspec.yaml`（如 **1.0.4**）。数据为本地 JSON + 附件；iOS 越狱侧通过 **deb** 安装到 `/Applications`。生产后端为 **`server-php/`**。

## 发行版产品约定（重要）

- **最终用户不看到 API 域名**：Release 构建下，登录页 / 账号页 / 关于页 **不展示、不编辑** 服务器地址；内置默认云端入口，错误文案只说「云服务 / 网络」。
- **调试例外**：Debug / Profile 仍显示「服务器地址（仅调试）」便于联调。
- 域名与部署细节只写在运维文档（`server-php/DEPLOY_*.md`、`BUILD_AND_DEPLOY.md`），**不要**写进面向司机的 UI 文案。

## 新机器最短路径

1. `flutter pub get`，`flutter doctor -v` 确认环境（Linux/WSL 使用 **本机可执行的** Flutter，不要用 Windows 分区里只有 exe 的 SDK）。
2. `cp dev/machine.env.example dev/machine.env`，填写 **`GITHUB_REPO`**（可空，会从 `git remote` 推断）、**`FLUTTER_BIN_PATH`**、`DEVICE_PASS`（越狱 SSH）、可选 **`GIT_*`**、服务端 **`SERVER_*`**。
3. 可选：`./dev/apply_git_config.sh` 写入本仓库 `user.name` / `user.email` / `remote.origin.url`。
4. iOS 无 Xcode：`gh auth login`，推送代码触发 **iOS Runner.app Build**，再用一键脚本拉产物。
5. VS Code：**运行任务** → 「一键：…」系列（见 `.vscode/tasks.json`）。

## 配置从哪来

- **`dev/machine.env`**（gitignore）：单一本机配置文件；由 **`scripts/project_env.sh`** 与 **`deploy.sh` / `debug.sh` / 一键脚本** 自动加载。
- **`.device.env`**（仍支持，gitignore）：若存在，在 `machine.env` **之后**加载，可覆盖前者。

## 一键脚本（项目根）

**注意**：一键 ipa / 一键 deb 安装使用的是 **CI 已构建的 Runner.app**，与当前工作区代码一致的前提是：**改动已 push 且「iOS Runner.app Build」已成功**。仅本地改代码未推远程时，打出来仍是旧包；Mac 本机可直接 `flutter build ios` 后跑 `package_deb.sh` / `package_ipa.sh`。

| 脚本 | 作用 |
|------|------|
| `./one_click_ipa.sh` | `gh` 拉最新成功 CI 的 Runner.app → `ipa-out/Runner.ipa` |
| `./one_click_deb_install.sh` | 拉 CI → 打 deb → SSH `dpkg -i` |
| `./one_click_apk_install.sh` | 本机 `flutter build apk --release` → 自动发现设备 → `adb install -r` |
| `./one_click_find_android.sh` | 仅扫描/连接 Android（打印 serial） |
| `./one_click_server_deploy.sh` | rsync 部署 `server-php/`（保留远端 config.php / data） |
| `make ipa-one` / `make deb-install-one` / `make apk-install-one` / `make server-deploy` | 同上 |

均需：**`gh` 已登录**；deb 安装需 **`python3` + paramiko`**，设备密码在 **`dev/machine.env`** 或通过环境变量传入。

## 关键文件

| 路径 | 说明 |
|------|------|
| `BUILD_AND_DEPLOY.md` | 给人看的完整手册 |
| `dev/machine.env.example` | 本机配置模板 |
| `scripts/project_env.sh` | 加载 machine.env + .device.env |
| `scripts/with_project_env.sh` | 供任务包装；支持任务里传入的 `DEVICE_PASS` 覆盖配置 |
| `package_deb.sh` / `package_ipa.sh` / `deploy.sh` | deb / ipa / 安装 |
| `scripts/discover_android_adb.py` | 局域网/USB 自动发现 Android adb |
| `.github/workflows/ios-runner-app-build.yml` | macOS 上编 Runner.app |
| `lib/state/auth_controller.dart` | 内置默认云端 URL（不进 Release UI） |
| `lib/ui/login_screen.dart` / `account_screen.dart` / `about_screen.dart` | Release 隐藏域名展示 |

## 业务常量备忘

- ETC 对账手续费：**0.35%**（`lib/services/profit_calculator.dart` 中 `etcTollReconcileRate = 0.0035`）。

## 发行版云端能力（server-php）

- **控制面** `/api/app/check`：停服 / 强更 / 设备吊销 / 离线宽限；管理后台可改。
- **同步**：账本 `revision` 乐观锁；冲突 409；客户端 SyncEngine + 冲突 UI。
- **用户运营**：注册默认试用、到期只读/禁登、延期/转正/踢下线。
- **触达**：站内信 `/api/messages`；可选 FCM（`fcm_server_key`）。
- **功能开关**：`feature_flags`（导出/导入/消息/Web）。
- **运维**：审计、自动快照恢复、设备管理、`/api/health?deep=1`。
- **部署**：`./one_click_server_deploy.sh`；CI：iOS Runner.app + Android APK Release。

## 关于页版本 / 构建号

- 关于里「版本 / 构建」来自 **`package_info_plus`**，与 **`flutter build`** 写入的 `--build-name` / `--build-number` 一致。
- 打包脚本与 CI 会通过 **`scripts/flutter_build_version_env.sh`** 自动注入构建号（CI 用 `GITHUB_RUN_NUMBER`，本机用 `git rev-list --count HEAD`），无需每次手改 `pubspec.yaml` 的 `+` 后缀。
- 改营销版本号（如 `1.0.3` → `1.0.4`）时改 **`pubspec.yaml` 的 `version:` 行**。

## 账本导入 / 导出备份

- **导出备份…**：生成 ZIP（`ledger_book.json` + `attachments/` 内引用的图片），经系统分享保存。
- **导入账本…**：支持本应用导出的 **`.zip`** 或 **`.json`**；ZIP 会一并恢复附件。支持 **合并** / **覆盖**（二次确认）。
- 实现：`ledger_backup_exporter.dart`、`ledger_backup_importer.dart`。

## 不要提交

- `dev/machine.env`、`.device.env`、密钥、PAT、SSH 私钥、`packages/`、`ipa-out/` 等（见 `.gitignore`）。
