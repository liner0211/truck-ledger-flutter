# 本机开发配置目录

| 文件 | 是否入库 | 说明 |
|------|----------|------|
| **`machine.env.example`** | 是 | 复制为 `machine.env` 后填写本机路径与密钥 |
| **`machine.env`** | 否（gitignore） | 你的真实配置，勿提交 |
| **`apply_git_config.sh`** | 是 | 将 `machine.env` 中的 `GIT_*` 写入本仓库 `git config --local` |

完整编译 / 装包见 **[`BUILD_AND_DEPLOY.md`](../BUILD_AND_DEPLOY.md)**；迁机与 Secrets 见 **[`docs/MIGRATION.md`](../docs/MIGRATION.md)**；AI 索引见 **[`AGENTS.md`](../AGENTS.md)**。

关于页 **构建号** 由 CI 经 **`scripts/flutter_build_version_env.sh`** 注入（`GITHUB_RUN_NUMBER`），一般不必手改 `pubspec.yaml` 的 `+` 后缀。
