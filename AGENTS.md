# 给 AI 助手 / 新对话的快速上下文

在新 Cursor 窗口接手本项目时，先读 **`BUILD_AND_DEPLOY.md`**（全流程），再读本文件（索引）。

## 项目目的

Flutter 版「卡车记账」，包名 `com.liner0211.truckledger`。数据为本地 JSON + 附件；iOS 越狱侧通过 **deb** 安装到 `/Applications`。

## 新机器最短路径

1. `flutter pub get`，`flutter doctor -v` 确认环境（Linux/WSL 使用 **本机可执行的** Flutter，不要用 Windows 分区里只有 exe 的 SDK）。
2. `cp dev/machine.env.example dev/machine.env`，填写 **`GITHUB_REPO`**（可空，会从 `git remote` 推断）、**`FLUTTER_BIN_PATH`**、`DEVICE_PASS`（越狱 SSH）、可选 **`GIT_*`**。
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
| `./one_click_apk_install.sh` | 本机 `flutter build apk --release` → `adb install -r` |
| `make ipa-one` / `make deb-install-one` / `make apk-install-one` | 同上 |

均需：**`gh` 已登录**；deb 安装需 **`python3` + paramiko**，设备密码在 **`dev/machine.env`** 或通过环境变量传入。

## 关键文件

| 路径 | 说明 |
|------|------|
| `BUILD_AND_DEPLOY.md` | 给人看的完整手册 |
| `dev/machine.env.example` | 本机配置模板 |
| `scripts/project_env.sh` | 加载 machine.env + .device.env |
| `scripts/with_project_env.sh` | 供任务包装；支持任务里传入的 `DEVICE_PASS` 覆盖配置 |
| `package_deb.sh` / `package_ipa.sh` / `deploy.sh` | deb / ipa / 安装 |
| `.github/workflows/ios-runner-app-build.yml` | macOS 上编 Runner.app |

## 业务常量备忘

- ETC 对账手续费：**0.35%**（`lib/services/profit_calculator.dart` 中 `etcTollReconcileRate = 0.0035`）。

## 不要提交

- `dev/machine.env`、`.device.env`、密钥、PAT、`packages/`、`ipa-out/` 等（见 `.gitignore`）。
