# 卡车记账（Flutter）

离线优先的司机 / 小车队记账 App。包名 **`com.liner0211.truckledger`**，显示名 **卡车记账**。本地 JSON + 附件；可选登录后与云端同步。

**当前版本**：见 `pubspec.yaml`（如 `1.0.4`）。

## 发行说明（面向用户）

- Release 包**不展示**云端 API 域名；用户只需注册 / 登录，后台自动连内置云服务。
- 调试构建（Debug / Profile）仍可改服务器地址，便于开发联调。
- 运维与域名配置见 `server-php/` 与 [`BUILD_AND_DEPLOY.md`](./BUILD_AND_DEPLOY.md)，勿写入司机可见文案。

## 从哪里开始

| 读者 | 文档 |
|------|------|
| 新机器编译 / 装包 / CI | [`BUILD_AND_DEPLOY.md`](./BUILD_AND_DEPLOY.md) |
| AI / 新对话上下文 | [`AGENTS.md`](./AGENTS.md) |
| PHP 后端与宝塔 | [`server-php/README.md`](./server-php/README.md) |

克隆后：`cp dev/machine.env.example dev/machine.env`，填写 `FLUTTER_BIN_PATH`、`DEVICE_PASS`、`GITHUB_REPO`、可选 `SERVER_*`。

```bash
flutter pub get
flutter doctor -v
```

### 一键（需 `gh` / adb / 越狱 SSH 等，见手册）

```bash
./one_click_apk_install.sh      # Release APK → 已连接设备
./one_click_ipa.sh              # CI Runner.app → ipa
./one_click_deb_install.sh      # CI → deb → 越狱机
./one_click_server_deploy.sh    # 同步 server-php（保留远端 config.php / data）
```

或 VS Code 任务：「一键：…」系列。

## 云端能力摘要

控制面（停服 / 强更 / 设备）、账本 `revision` 冲突可见、试用与到期、站内信、管理后台 `/admin`。部署与健康检查细节见 `server-php/`。

## 与其他版本并存

- 同一 Android 设备上包名相同则不能与旧 Kotlin 版共存。
- iOS 越狱 deb 与签名包若 Bundle ID 相同也可能冲突。

## 不要提交

`dev/machine.env`、`.device.env`、密钥、私钥、`packages/`、`ipa-out/` 等（见 `.gitignore`）。
