<?php
/**
 * 复制为 config.php 并修改密钥。
 * 生产域名：https://truck.liner0211.online
 * 宝塔：网站根目录指向 public/，PHP 8.0
 */
return [
    'jwt_secret' => '请改成至少32位随机字符串',
    'admin_password' => '请改成强密码',
    'jwt_expire_sec' => 60 * 60 * 24 * 30,
    'max_upload_bytes' => 20 * 1024 * 1024,
];
