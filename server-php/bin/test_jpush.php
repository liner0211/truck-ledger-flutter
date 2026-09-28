<?php
/**
 * 本机/服务器诊断极光推送：php bin/test_jpush.php [user_id]
 */
declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/lib/JsonResponse.php';
require $root . '/lib/Database.php';
require $root . '/lib/PushService.php';

$cfg = require $root . '/config.php';
$pdo = Database::connect($cfg);

$st = PushService::status($cfg);
echo "push mode={$st['mode']} configured=" . ($st['configured'] ? 'yes' : 'no') . "\n";
if (!empty($st['detail'])) {
    echo "detail={$st['detail']}\n";
}

$userId = isset($argv[1]) ? (int)$argv[1] : 0;
if ($userId <= 0) {
    echo "用法: php bin/test_jpush.php <user_id>\n";
    exit($st['configured'] ? 0 : 1);
}

$r = PushService::sendToUser($pdo, $cfg, $userId, '极光测试', '若看到本通知，系统推送已打通', [
    'type' => 'inbox',
    'payload' => 'hub:0',
]);
echo 'sent=' . $r['sent'] . ' skipped=' . $r['skipped'] . "\n";
foreach ($r['errors'] as $e) {
    echo "error: $e\n";
}
exit($r['sent'] > 0 ? 0 : 1);
