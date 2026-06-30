# DNSPod：子域名 truck.liner0211.online

子域名完全可以正常使用。App 连不上且报 `Failed host lookup` 时，是 **DNS 记录未生效或填错**，与手机权限、Nginx 业务逻辑无关。在 DNSPod 修正即可，**无需改手机系统设置**。

## 正确记录（DNSPod 控制台）

域名 **liner0211.online** → **记录管理**：

| 主机记录 | 类型 | 记录值 | TTL |
|----------|------|--------|-----|
| `truck` | **A** | 宝塔服务器公网 IP（如 `43.155.110.38`） | 600 |

注意：

- 主机记录只填 **`truck`**，不要填 `truck.liner0211.online`
- 类型必须是 **A**，记录值为服务器 IP
- 不要用 CNAME 指到尚未解析的域名（除非明确需要）

## 常见错误

| 现象 | 原因 |
|------|------|
| App 报 `No address associated with hostname` | 无 `truck` 的 A 记录，或刚添加未生效 |
| 浏览器有时能开、App 不行 | 多为 DNS 缓存/刚生效，等几分钟或重开 App |
| 解析到错误 IP | `@` 有多条冲突 A 记录，与 truck 无关但需检查 truck 单独一条 |

## 验证（添加/修改后等 1～10 分钟）

```bash
# 电脑或服务器上
dig +short truck.liner0211.online A
# 应只返回你的服务器 IP

curl -s https://truck.liner0211.online/api/health
# 应返回 {"status":"ok"}
```

手机浏览器打开同一 health 地址，能打开则 App 也应能连（服务器地址填 `https://truck.liner0211.online`）。

## 宝塔侧（与子域名配套）

1. 站点 **域名** 包含 `truck.liner0211.online`
2. **运行目录** 为 `public`
3. Nginx 见 `nginx.truck.liner0211.online.conf`（`server_name truck.liner0211.online;`）
4. SSL 证书包含 `truck.liner0211.online`

子域名与主域名 **不必** 绑在同一站点；只保证 `truck` 的 A 记录指向本服务器即可。

## App 服务器地址

```
https://truck.liner0211.online
```
