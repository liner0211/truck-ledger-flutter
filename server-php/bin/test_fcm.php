#!/usr/bin/env php
<?php
/**
 * 本机/服务器诊断 FCM：php bin/test_fcm.php [user_id]
 * 会向该用户已登记的非 local token 发一条测试通知。
 */
declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/lib/JsonResponse.php';
require $root . '/lib/PushService.php';
require $root . '/lib/MessageService.php';
require $root . '/lib/RealtimeHub.php';
require $root . '/lib/Database.php';
require $root . '/lib/Config.php';

$cfg = Config::load($root);
$pdo = Database::pdo($cfg);
$userId = isset($argv[1]) ? (int)$argv[1] : 0;

$st = PushService::status($cfg);
echo "FCM status: " . json_encode($st, JSON_UNESCAPED_UNICODE) . PHP_EOL;

$stmt = $pdo->query('SELECT user_id, platform, token, updated_at FROM push_tokens ORDER BY updated_at DESC');
$anyFcm = false;
foreach ($stmt as $row) {
    $local = str_starts_with((string)$row['token'], 'local:');
    if (!$local) {
        $anyFcm = true;
    }
    echo sprintf(
        "user=%s platform=%s kind=%s len=%d updated=%s\n",
        $row['user_id'],
        $row['platform'],
        $local ? 'LOCAL' : 'FCM',
        strlen((string)$row['token']),
        $row['updated_at']
    );
}
if (!$anyFcm) {
    echo "没有真 FCM token。客户端需成功 getToken 并上报后，系统通知栏才会有推送。\n";
    echo "常见原因：无 Google Play 服务、未允许通知权限、Firebase 未加 Release 签名 SHA-1。\n";
    exit(2);
}
if ($userId <= 0) {
    echo "用法: php bin/test_fcm.php <user_id>\n";
    exit(0);
}
$r = PushService::sendToUser($pdo, $cfg, $userId, 'FCM 测试', '若看到本通知，系统推送已打通', [
    'type' => 'inbox',
]);
echo "send result: " . json_encode($r, JSON_UNESCAPED_UNICODE) . PHP_EOL;
