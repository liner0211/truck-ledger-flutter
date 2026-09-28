<?php
/**
 * 复制为 config.php 并修改密钥。
 * 生产域名：https://truck.liner0211.online
 * 宝塔：网站根目录指向 public/，PHP 8.0
 *
 * 生成管理员密码哈希（推荐）：
 *   php -r "echo password_hash('你的强密码', PASSWORD_BCRYPT), PHP_EOL;"
 * 填到 admin_password_hash；可留空 admin_password。
 */
return [
    'jwt_secret' => '请改成至少32位随机字符串',
    // 兼容旧配置：明文密码（生产请改用 admin_password_hash）
    'admin_password' => '请改成强密码',
    'admin_password_hash' => '',
    // 首次迁移写入 admins 表的超级管理员用户名
    'admin_username' => 'liner0211',
    'jwt_expire_sec' => 60 * 60 * 24 * 30,
    'admin_jwt_expire_sec' => 60 * 60 * 24 * 7,
    'max_upload_bytes' => 20 * 1024 * 1024,
    // CORS：生产建议改为具体域名列表，例如 ['https://truck.liner0211.online']
    'cors_origins' => ['*'],
    // FCM（海外/有 GMS，可选）
    'fcm_service_account_file' => 'data/fcm-service-account.json',
    'fcm_project_id' => '',
    'fcm_server_key' => '',
    // 极光推送（国内主通道；AppKey 会下发给客户端，Master Secret 仅服务端）
    'jpush_app_key' => '',
    'jpush_master_secret' => '',
    // iOS 正式环境证书时设 true；开发包 false
    'jpush_apns_production' => false,
    // WebSocket 实时通道。本机跑：bash ws/start_ws.sh；Nginx 反代 /ws
    'ws_enabled' => true,
    'ws_port' => 8765,
    'ws_publish_url' => 'http://127.0.0.1:8765/publish',
    // 留空则用 hash(jwt_secret|ws-internal)；与 start_ws.sh 一致
    'ws_internal_token' => '',
    // CI 发布版本令牌（GitHub Actions 调 /api/ci/publish-release）；请改为长随机串
    'ci_publish_token' => '',
];
