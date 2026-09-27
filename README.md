# 卡车记账（Flutter）

离线优先的司机 / 小车队记账 App。包名 **`com.liner0211.truckledger`**，显示名 **卡车记账**。本地 JSON + 附件；可选登录后与云端同步。

**当前版本**：见 [`pubspec.yaml`](./pubspec.yaml)。

## 发行说明（面向用户）

- Release 包**不展示**云端 API 域名；用户只需注册 / 登录，后台自动连内置云服务。
- 调试构建（Debug / Profile）仍可改服务器地址，便于开发联调。
- 运维与域名配置见 `server-php/` 与 [`BUILD_AND_DEPLOY.md`](./BUILD_AND_DEPLOY.md)，勿写入司机可见文案。

## 从哪里开始

| 读者 | 文档 |
|------|------|
| 新机器编译 / 装包 / 一键发版 | [`BUILD_AND_DEPLOY.md`](./BUILD_AND_DEPLOY.md) |
| 换机 / 换服 / GitHub Secrets | [`docs/MIGRATION.md`](./docs/MIGRATION.md) |
| AI / 新对话上下文 | [`AGENTS.md`](./AGENTS.md) |
| PHP 后端与 API | [`server-php/README.md`](./server-php/README.md) |
| 生产宝塔逐步部署 | [`server-php/DEPLOY_truck.liner0211.online.md`](./server-php/DEPLOY_truck.liner0211.online.md) |

克隆后：`cp dev/machine.env.example dev/machine.env`，填写 `FLUTTER_BIN_PATH`、`DEVICE_PASS`、可选 `GITHUB_REPO` / `SERVER_*`。详见 [`docs/MIGRATION.md`](./docs/MIGRATION.md)。

```bash
flutter pub get
flutter doctor -v
```

### 一键（需 `gh` / adb / 越狱 SSH 等，见手册）

```bash
./one_click_ship.sh             # 总控：commit(可选) → push → 等 CI → 可选装包
./one_click_apk_install.sh      # 拉取 CI/生产 APK → adb 安装
./one_click_ipa.sh              # 拉取 CI/生产 IPA
./one_click_deb_install.sh      # 拉取 CI/生产 deb → 越狱机
./one_click_server_deploy.sh    # 同步 server-php（保留远端 config.php / data）
```

发布包一律由 GitHub Actions 编译；本机脚本只下载安装。CI 细节见 [`docs/CI_AUTO_RELEASE.md`](./docs/CI_AUTO_RELEASE.md)。

或 VS Code 任务：「一键：…」系列。

## 云端能力摘要

控制面（停服 / 强更 / 设备）、账本 `revision` 冲突可见、试用与到期、站内信、管理后台 `/admin`、Web `/app/`。细节见 [`server-php/README.md`](./server-php/README.md)。

## 与其他版本并存

- 同一 Android 设备上包名相同则不能与旧 Kotlin 版共存。
- iOS 越狱 deb 与签名包若 Bundle ID 相同也可能冲突。

## 不要提交

`dev/machine.env`、`.device.env`、密钥、私钥、`packages/`、`ipa-out/`、`android/build/` 等（见 [`.gitignore`](./.gitignore)）。
