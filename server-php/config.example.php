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
    'jwt_expire_sec' => 60 * 60 * 24 * 30,
    'max_upload_bytes' => 20 * 1024 * 1024,
    // CORS：生产建议改为具体域名列表，例如 ['https://truck.liner0211.online']
    'cors_origins' => ['*'],
    // 可选：Firebase Cloud Messaging Legacy Server Key；不配则仅站内信
    'fcm_server_key' => '',
];
