# 卡车记账 · 管理端（Flutter）

Android / Windows / Linux 客户端，对接 `/api/admin/*`。

## 运行

```bash
cd admin_app
flutter pub get
flutter run -d linux          # 或 windows / android
```

Release 默认服务器：`https://truck.liner0211.online`  
Debug 可在登录页改服务器地址。

## 权限

- **super**：控制面、删用户、运营账号管理
- **operator**：用户运营、消息

首次 Web/API 登录会从 `config.php` 的 `admin_username` + 密码种子超级管理员。
