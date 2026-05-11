# truck_ledger_flutter（卡车记账 · Flutter）

与 **Theos iOS（Swift）**、Kotlin 安卓版并列的 Flutter 工程；包名 **`com.liner0211.truckledger`**，显示名 **卡车记账**。数据为本地 JSON + 附件目录，可与原版 iOS 数据格式对齐使用。

## 新环境从哪里开始

**完整步骤（编译、CI、deb/ipa、越狱安装、环境变量、常见问题）见：[`BUILD_AND_DEPLOY.md`](./BUILD_AND_DEPLOY.md)。**  
**新 Cursor / AI 对话请先读：[`AGENTS.md`](./AGENTS.md)。**

克隆后第一步建议：`cp dev/machine.env.example dev/machine.env`，按需填写 **`FLUTTER_BIN_PATH`**、**`DEVICE_PASS`**、**`GITHUB_REPO`** 等；可选 `./dev/apply_git_config.sh` 写入本仓库 Git 用户名与 `origin`。

**VS Code**：`终端 → 运行任务` → 例如「**一键：Android 打包并安装到设备**」「**一键：iOS deb（CI）打包并安装越狱机**」等（见 `.vscode/tasks.json`）。

下面仅保留最短备忘。

### Flutter

- 安装 **Flutter stable**，确保使用 **当前系统可执行的 SDK**（Linux/WSL 不要用 Windows 分区里只有 `.exe` 的 Flutter）。
- 验证：`flutter doctor -v`，在项目根执行：`flutter pub get`。

### Android

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

可使用 `./scripts/build_apk.sh`；新机器请设置 `FLUTTER_BIN_PATH` 指向你的 `flutter/bin`。

### iOS

- **本机有 macOS + Xcode**：可直接 `flutter build ios --release --no-codesign`，再 `./package_deb.sh` / `./package_ipa.sh`。
- **无 Xcode（如 Linux/WSL）**：用 **GitHub Actions** 构建 `Runner.app`，本机通过 **`gh`** 拉取产物后打包。

一键（需 `gh auth login`，deb 安装还需 `dev/machine.env` 与 `paramiko`）：

```bash
./one_click_ipa.sh           # → ipa-out/Runner.ipa
./one_click_deb_install.sh   # CI Runner.app → deb → SSH 安装越狱机
./one_click_apk_install.sh   # 本机 Release APK → adb 安装（需 adb、已连接设备）
```

或：`make ipa-one`、`make deb-install-one`、`make apk-install-one`。

### 本机配置（勿提交）

推荐 **`dev/machine.env`**（从 `dev/machine.env.example` 复制，已 gitignore）。仍可使用项目根 **`.device.env`**（在 `machine.env` 之后加载）。详见 [`BUILD_AND_DEPLOY.md`](./BUILD_AND_DEPLOY.md) 第 3 节。

## 与其他版本的并存

- **同一 Android 设备**上包名相同则不能同时安装 Flutter APK 与旧 Kotlin 版，调试前请卸载其一或临时修改一方 `applicationId`。
- **iOS**：越狱 deb 与 Xcode/TestFlight 签名包若 Bundle ID 相同也可能冲突，按需区分。

## 文档与脚本索引

| 文档 / 脚本 | 用途 |
|-------------|------|
| [**BUILD_AND_DEPLOY.md**](./BUILD_AND_DEPLOY.md) | 新机器全流程手册 |
| `package_deb.sh` / `package_ipa.sh` | deb / ipa |
| `deploy.sh` / `debug.sh` | 越狱机安装与调试 |
| `.github/workflows/ios-runner-app-build.yml` | macOS 上构建 Runner.app |
