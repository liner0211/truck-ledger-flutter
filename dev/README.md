# 本机开发配置目录

| 文件 | 是否入库 | 说明 |
|------|----------|------|
| **`machine.env.example`** | 是 | 复制为 `machine.env` 后填写本机路径与密钥 |
| **`machine.env`** | 否（gitignore） | 你的真实配置，勿提交 |
| **`apply_git_config.sh`** | 是 | 将 `machine.env` 中的 `GIT_*` 写入本仓库 `git config --local` |

完整编译、CI、deb/ipa、安装流程见仓库根目录 **[`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md)**；给 AI 的短索引见 **[`AGENTS.md`](../AGENTS.md)**。

Android 一键安装依赖 **`ANDROID_SERIAL`**（仅多设备时）：见 **`machine.env.example`**。

关于页显示的 **构建号** 在每次 `flutter build` 时由 **`scripts/flutter_build_version_env.sh`** 自动注入（CI 用 `GITHUB_RUN_NUMBER`，本机用 `git` 提交计数），一般不必手改 `pubspec.yaml` 的 `+` 后缀。
