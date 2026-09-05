# 卡车记账 · 管理端（Flutter）

Android / iOS / Windows / Linux，对接 `/api/admin/*`。

**发布包一律由 CI 编译**（workflow：`Release Admin Packages`）。

## 角色

| 角色 | 说明 |
|------|------|
| **开发者**（`super`） | 你本人：控制面、删用户、会计账号管理、设备吊销、快照恢复等底层能力 |
| **会计管理员**（`operator`） | 给公司会计：用户运营、查看/修改账本、发消息、导出 Excel；不能动控制面与底层运维 |

创建的会计管理员可禁用 / 重置密码 / **删除**（不可删开发者账号）。

## 能力

- 用户列表运营（延期/转正/踢下线等）
- 点进用户可查看账本、切换交账标记、高级 JSON 编辑、**导出 Excel**
- 开发者专属：控制面、会计账号管理

## 运行

```bash
cd admin_app
flutter pub get
flutter run -d linux          # 或 windows / android / ios
```
