# 部署：truck.liner0211.online（宝塔 8.0 + PHP 8.0）

按本文在宝塔上部署 `server-php/`，域名 **`https://truck.liner0211.online`**。

---

## 一、上传代码

1. 将仓库中整个 **`server-php/`** 目录上传到服务器  
2. 推荐路径（宝塔默认按域名建目录）：

```
/www/wwwroot/truck.liner0211.online/
├── public/
├── lib/
├── templates/
├── config.example.php
└── ...
```

可用宝塔 **文件** 上传 zip 后解压，或用 SFTP / Git。

### 本机一键同步（推荐）

在开发机配置 `dev/machine.env`：

```bash
SERVER_HOST=truck.liner0211.online
SERVER_USER=root
SERVER_PATH=/www/wwwroot/truck.liner0211.online
SERVER_HEALTH_URL=https://truck.liner0211.online/api/health?deep=1
```

然后：

```bash
./one_click_server_deploy.sh
# 或 make server-deploy
# 或 VS Code 任务：「一键：部署 PHP 后端」
```

脚本用 rsync 同步代码，**不会覆盖**远端 `config.php` 与 `data/`。

### 试用到期提醒（宝塔计划任务）

每日执行：

```bash
cd /www/wwwroot/truck.liner0211.online && php bin/notify_trial_expiring.php --days=3
```

---

## 二、创建 config.php

SSH 或宝塔 **终端**：

```bash
cd /www/wwwroot/truck.liner0211.online
cp config.example.php config.php
nano config.php   # 或用宝塔文件编辑器
```

修改为（**jwt_secret 必须换成长随机串**）：

```php
<?php
return [
    'jwt_secret' => '在这里粘贴32位以上随机字符串',
    'admin_password' => '你的管理后台密码',
    'jwt_expire_sec' => 60 * 60 * 24 * 30,
    'max_upload_bytes' => 20 * 1024 * 1024,
];
```

生成随机密钥示例：

```bash
openssl rand -hex 32
```

---

## 三、宝塔添加网站

**网站** → **添加站点**

| 项 | 填写 |
|----|------|
| 域名 | `truck.liner0211.online` |
| 根目录 | `/www/wwwroot/truck.liner0211.online/public` |
| FTP / 数据库 | 不需要，可不创建 |
| PHP 版本 | **PHP-8.0** |

添加完成后 → 站点 **设置** → **网站目录**：

- **运行目录** 选择 **`/public`**（若界面是相对路径则选 `public`）
- 防跨站 **关闭**（或保持默认，确保 `public` 为入口）

---

## 四、SSL 证书

站点 **设置** → **SSL**：

1. **Let's Encrypt** → 勾选 `truck.liner0211.online` → 申请
2. 开启 **强制 HTTPS**

---

## 五、Nginx 配置（PHP 8.0）

站点 **设置** → **配置文件**，在 `server { ... }` 内找到 PHP 段，确保包含以下内容。

在 `server` 块**靠前**位置加：

```nginx
client_max_body_size 25m;

# ★ 必加：否则 /api/attachments/xxx.jpg 会被下方「静态 jpg」规则拦截 → App 上传附件 404
location ^~ /api/ {
    try_files $uri /index.php?$query_string;
}

location ^~ /admin/ {
    try_files $uri /index.php?$query_string;
}
```

在 `location ~ \.php$` 或 `include enable-php-80.conf` 附近加 **Authorization 转发**（App 登录必需）：

```nginx
location / {
    try_files $uri $uri/ /index.php?$query_string;
}

# 宝塔 PHP 8.0 通常已有类似块，在 fastcgi_pass 那段里加一行：
location ~ [^/]\.php(/|$) {
    try_files $uri =404;
    fastcgi_pass unix:/tmp/php-cgi-80.sock;   # 宝塔可能自动生成，勿随意改 sock 路径
    fastcgi_index index.php;
    include fastcgi.conf;
    include pathinfo.conf;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
}
```

> 宝塔 8.0 若已有 `include enable-php-80.conf;`，只需在该 `location` 块内**追加一行**：
>
> ```nginx
> fastcgi_param HTTP_AUTHORIZATION $http_authorization;
> ```

保存 → **重载配置**。

参考完整片段见同目录 [`nginx.truck.liner0211.online.conf`](./nginx.truck.liner0211.online.conf)。

---

## 六、目录权限

```bash
mkdir -p /www/wwwroot/truck.liner0211.online/data/attachments
chown -R www:www /www/wwwroot/truck.liner0211.online/data
chmod -R 755 /www/wwwroot/truck.liner0211.online/data
```

也可在宝塔 **文件** 里对 `data` 目录设为 `www` 可写。

---

## 七、DNS 解析

在域名服务商处添加 **A 记录**：

| 主机记录 | 类型 | 值 |
|----------|------|-----|
| `truck` | A | 你的服务器公网 IP |

等待生效后 ping `truck.liner0211.online` 应指向服务器 IP。

---

## 八、验证

浏览器访问：

| URL | 期望结果 |
|-----|----------|
| https://truck.liner0211.online/api/health | `{"status":"ok"}` |
| https://truck.liner0211.online/admin | 管理后台登录页 |
| https://truck.liner0211.online/app/ | **Web 云端账本**（与 App 同账号登录） |

管理后台用户列表中可点 **查看账本**，在浏览器编辑任意用户数据。

命令行：

```bash
curl -s https://truck.liner0211.online/api/health
# 附件路由应返回 401（未登录），若是 404 说明 Nginx 未把 .jpg 请求交给 PHP
curl -s -o /dev/null -w "%{http_code}\n" https://truck.liner0211.online/api/attachments/test.jpg
```

---

## 九、手机 App

登录页 **服务器地址**（已写入 App 默认值）：

```
https://truck.liner0211.online
```

1. 注册账号  
2. 「更多 → 账号与同步 → 测试连接」应显示正常  
3. 管理后台用 `config.php` 里的 `admin_password` 登录

---

## 十、防火墙

- 云厂商安全组：放行 **80**、**443**
- 宝塔 **安全**：放行 80、443  
- **无需** 对外开放 8080

---

## 十一、备份

宝塔 **计划任务** → 每天压缩：

```
/www/wwwroot/truck.liner0211.online/data/
```

---

## 常见问题

| 现象 | 处理 |
|------|------|
| 404 除首页外全失败 | 检查 `try_files` 和运行目录是否为 `public` |
| App 401 无法登录 | 加 `fastcgi_param HTTP_AUTHORIZATION $http_authorization;` |
| 502 | PHP 8.0 是否安装；看 `/www/wwwlogs/truck.liner0211.online.error.log` |
| 上传附件失败 **404** | **最常见**：宝塔默认 `location ~ .*\.jpg$` 抢走了 `/api/attachments/xxx.jpg`，未进 PHP。在 `server` 内加入 `location ^~ /api/` 与 `location ^~ /admin/`（见第五节），重载 Nginx 后 `curl` 附件 URL 应得 **401** 而非 404 |
| 上传附件失败 400/500 | `client_max_body_size 25m` + `data/attachments` 可写 |
| SSL 申请失败 | DNS 是否已指向本机；80 端口是否可达 |

---

## 与 App 打包

修改默认服务器后需重新安装 APK：

```bash
./scripts/one_click_apk_install.sh
```

或本地：`flutter build apk --release`
