# 卡车记账 Flutter — 编译、打包与部署手册

本文档面向在新电脑 / 新环境中恢复开发与一键产出 **Android APK**、**越狱 deb**、**IPA 容器** 的流程整理（含此前踩坑与约定）。

---

## 1. 项目是什么

| 项 | 说明 |
|----|------|
| 用途 | 车队记账：圈次、路线、费用、垫付、分成、Excel 导出等 |
| 包名 | `com.liner0211.truckledger`，桌面名「卡车记账」 |
| 数据 | 本地 JSON（`ledger_book.json` + `attachments/`，与原版 Swift 时间戳兼容） |
| iOS 越狱安装 | 安装到 `/Applications` 的 **deb**（非 App Store 流程） |

---

## 2. 新机器 Checklist

按顺序准备即可在新环境「可控」编译与生成产物。

### 2.1 通用

- [ ] **Git**、克隆本仓库
- [ ] **本机配置文件（推荐第一步）**  
  - `cp dev/machine.env.example dev/machine.env`  
  - 填写 **`FLUTTER_BIN_PATH`**、`DEVICE_PASS`（若要用一键安装 deb）、可选 **`GITHUB_REPO`**、**`GIT_*`**（见文件内注释）  
  - 可选：写入 `GIT_USER_NAME` / `GIT_USER_EMAIL` / `GIT_REMOTE_URL` 后执行 **`./dev/apply_git_config.sh`**，一次性写入本仓库 **local** 的 git 用户与 `origin`  
- [ ] **Flutter SDK（Linux/macOS 原生路径）**  
  - WSL/Linux 下请勿使用 Windows 分区上的 Flutter（例如仅有 `dart.exe` 的安装），应在 Linux 侧安装 Flutter 并加入 `PATH`。  
  - 验证：`flutter doctor -v`
- [ ] 项目目录执行：`flutter pub get`
- [ ] **新 AI / 协作者**：阅读根目录 **[`AGENTS.md`](./AGENTS.md)**（索引 + 约定）

### 2.2 仅 Android

- [ ] **Android SDK**（或通过 Android Studio 安装）
- [ ] `flutter doctor --android-licenses`
- [ ] **adb** 可用，USB 调试或局域网 `adb connect`

### 2.3 仅 iOS（本机有 macOS + Xcode）

- [ ] **Xcode**、`flutter build ios --release --no-codesign` 可直接在本机生成 `build/ios/iphoneos/Runner.app`
- [ ] 之后可用仓库内 `package_deb.sh` / `package_ipa.sh`（见下文「手动打包」）

### 2.4 iOS 在无 Xcode 的机器上（例如 Linux / WSL）

- [ ] 代码推到 **GitHub**，仓库上有 Workflow：**iOS Runner.app Build**（macOS Runner 上执行 `flutter build ios`）
- [ ] 安装 [**GitHub CLI `gh`**](https://cli.github.com/) 并完成登录  
  - `gh auth login`  
  - Personal Access Token 建议权限：**repo**、**workflow**、**read:org**（否则 `gh` 可能报错）
- [ ] **Git 推送**建议用 **SSH**：`git remote set-url origin git@github.com:OWNER/REPO.git`
- [ ] 打 **deb** 需要：**`dpkg-deb`**，常见用法为 **`fakeroot dpkg-deb`**（Debian/Ubuntu/WSL：`sudo apt install fakeroot dpkg-dev`）
- [ ] **安装 deb 到越狱机**需要：**Python 3** + **`pip install paramiko`**

---

## 3. 本地文件约定（勿提交密钥）

| 文件 | 作用 |
|------|------|
| **`dev/machine.env`**（已 `.gitignore`，从 **`dev/machine.env.example`** 复制） | **推荐唯一本机配置**：`FLUTTER_BIN_PATH`、`GITHUB_REPO`、`DEVICE_*`、`GIT_*` 等；由 **`scripts/project_env.sh`** 自动加载 |
| **`.device.env`**（项目根，已 `.gitignore`） | 仍支持；在 `machine.env` **之后**加载，可覆盖同名变量 |
| **`.last_device_ip`** | 脚本缓存的上次成功 IP（若存在） |

所有 **`deploy.sh` / `debug.sh` / 一键脚本 / `fetch_runner_and_package_deb.sh`** 均会加载 `dev/machine.env`（及 `.device.env`）。VS Code 任务通过 **`./scripts/with_project_env.sh`** 注入环境；若在任务里填写了密码输入框，会**覆盖**配置文件中的 `DEVICE_PASS`（非空时）。

### VS Code 一键任务

打开 **终端 → 运行任务**，常用项包括：

- **一键：生成 APK（Release）**
- **一键：生成 IPA（CI 拉取 Runner.app）**
- **一键：拉取 CI 并打 deb（不安装）**
- **一键：deb 安装到越狱机**（可仅用 `machine.env` 中的密码，或使用任务里的密码框覆盖）

配置见 **`.vscode/tasks.json`**。

---

## 4. Android：编译与安装

```bash
cd truck_ledger_flutter
flutter pub get
flutter build apk --release   # 或 --debug
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

安装示例：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
# 或局域网设备（先 adb connect）
adb connect 192.168.x.x:5555
adb install -r ...
```

可选：`./scripts/build_apk.sh`（会先经 `with_project_env` 加载 **`dev/machine.env`** 中的 `FLUTTER_BIN_PATH`）：

```bash
./scripts/with_project_env.sh ./scripts/build_apk.sh --release
```

---

## 5. iOS：GitHub Actions 产出 Runner.app

- Workflow 文件：`.github/workflows/ios-runner-app-build.yml`
- 成功后在 Actions 页面下载 Artifact：**runner-app-ios**（内含 `Runner.app.zip`）
- **推送 `main` 通常会触发构建**；也可用：`gh workflow run "iOS Runner.app Build" --repo OWNER/REPO`

查询最近一次成功 run：

```bash
gh run list --repo OWNER/REPO --workflow "iOS Runner.app Build" --limit 5 \
  --json databaseId,headSha,status,conclusion,url
```

---

## 6. 一键脚本（推荐日常使用）

均在项目根执行；仓库默认识别 **`git remote origin`**（GitHub `owner/repo`），也可显式传入或使用 `GITHUB_REPO`。

| 脚本 | 作用 |
|------|------|
| **`./one_click_ipa.sh`** | 拉取最新成功 CI 的 `Runner.app` → 生成 **`ipa-out/Runner.ipa`**（容器；侧载需自行签名/TrollStore 等） |
| **`./one_click_deb_install.sh`** | 同上拉取 → **`package_deb.sh`** 打 deb → **`deploy.sh`** SSH 安装到越狱设备 |

依赖：**`gh` 已登录**；deb 安装还需 **`.device.env` 或 `DEVICE_PASS`** + **paramiko**。

可选指定仓库：

```bash
./one_click_deb_install.sh liner0211/truck-ledger-flutter
# 或
GITHUB_REPO=liner0211/truck-ledger-flutter ./one_click_ipa.sh
```

Makefile 等价：

```bash
make ipa-one          # 一键 IPA
make deb-install-one  # 一键 deb + 安装
```

---

## 7. 手动分步（调试 CI / 脚本时用）

```bash
# 下载最新成功 run 的 artifact 并解压到 build/ios/iphoneos/Runner.app，再打 deb
./scripts/fetch_runner_and_package_deb.sh          # 仓库从 remote 推断
# 或
./scripts/fetch_runner_and_package_deb.sh liner0211/truck-ledger-flutter

# 仅下载 Runner.app、不打 deb（给 ipa 用）
SKIP_PACKAGE_DEB=1 ./scripts/fetch_runner_and_package_deb.sh

# 已有 Runner.app 时只打 deb（跳过 flutter build）
SKIP_BUILD=1 ./package_deb.sh

# 已有 Runner.app 时只打 ipa
SKIP_BUILD=1 ./package_ipa.sh

# 已有 deb，只安装（会先 ./package_deb.sh；若已有 deb 可配合 SKIP_BUILD）
SKIP_BUILD=1 ./deploy.sh
```

deb 输出目录：**`packages/`**，文件名形如 `com.liner0211.truckledger_*_iphoneos-arm64e.deb`。

---

## 8. deb 与越狱机注意事项

- **`control`**：deb 元数据；版本号与 **`pubspec.yaml`** 的 `version:` 解析一致。
- **`package_deb.sh`**： staging 内会对 `Runner.app` 做权限规范化；deb 内含 **`DEBIAN/postinst`**，安装后在设备上执行 `chmod -R a+rX /Applications/Runner.app`，缓解部分越狱工具把框架改成 **700** 导致 **`mobile` 用户闪退**的问题。
- 仍闪退时可用仓库内 **`./debug.sh`**（同样可读 `.device.env`）配合设备日志排查。

---

## 9. 版本号与应用内展示

- **`pubspec.yaml`**：`version: x.y.z+build`（前半为版本名，后半为构建号）。
- **关于页**使用 **`package_info_plus`** 显示运行时版本；发布新包前记得递增 `version:`。

---

## 10. ETC 对账手续费

- 逻辑常量：`lib/services/profit_calculator.dart` 中 **`etcTollReconcileRate = 0.0035`**（即 **0.35%**）。
- UI / 导出文案需与之一致（详情页、费用编辑说明、Excel 导出等）。

---

## 11. 常见问题

| 现象 | 处理方向 |
|------|----------|
| WSL 里 `flutter` / `dart` 无法运行 | 使用 Linux 原生 Flutter，不要用 Windows 分区上的 SDK |
| `gh run list` / API 504 | 稍后重试；或用网页 Actions 查看 run id，`RUN_ID=xxx ./scripts/fetch_runner_and_package_deb.sh` |
| `deploy.sh` 要求 `DEVICE_PASS` | 配置 `.device.env` 或导出环境变量 |
| SSH `Connection refused` | 确认手机 IP、越狱 SSH 服务开启；或不写死错误 IP，删掉 `.device.env` 里错误的 `DEVICE_IP` 让脚本扫描 |
| 与旧 Kotlin 安卓共存 | 包名相同不能并存；调试一方前先卸载另一方或临时改 `applicationId` |

---

## 12. 相关文件索引

| 路径 | 说明 |
|------|------|
| `package_deb.sh` | 组装越狱 deb |
| `package_ipa.sh` | Payload  zip → ipa |
| `deploy.sh` | 发现设备、上传 deb、`dpkg -i`、`uicache` |
| `debug.sh` | SSH 侧调试辅助 |
| `scripts/fetch_runner_and_package_deb.sh` | `gh` 下载 artifact + 解压 +（可选）打 deb |
| `scripts/github_repo.sh` | 解析 `owner/repo` |
| `scripts/project_env.sh` | 加载 `dev/machine.env` + `.device.env` |
| `scripts/with_project_env.sh` | 任务/终端包装，支持临时覆盖 `DEVICE_PASS` 等 |
| `dev/apply_git_config.sh` | 将 `machine.env` 中 `GIT_*` 写入本仓库 `git config --local` |
| `AGENTS.md` | 给 AI / 新成员的短索引 |
| `.vscode/tasks.json` | 一键 APK / IPA / deb / 安装 |
| `Makefile` | `package` / `ipa` / `ipa-one` / `deb-install-one` 等 |

---

如有流程变更，优先更新本文档与 `.github/workflows` 注释，保持与新成员环境一致。
