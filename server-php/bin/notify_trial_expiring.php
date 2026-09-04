<?php
/**
 * 宝塔计划任务（每日）：扫描即将到期的试用用户，写入站内信（并尝试 FCM）。
 *
 * 用法（在 server-php 根目录）：
 *   php bin/notify_trial_expiring.php
 *   php bin/notify_trial_expiring.php --days=3
 */
declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/lib/Config.php';
require $root . '/lib/JsonResponse.php';
require $root . '/lib/Database.php';
require $root . '/lib/SettingsService.php';
require $root . '/lib/AttachmentService.php';
require $root . '/lib/EntitlementService.php';
require $root . '/lib/MessageService.php';
require $root . '/lib/PushService.php';

$days = 3;
foreach ($argv as $arg) {
    if (preg_match('/^--days=(\d+)$/', $arg, $m)) {
        $days = max(1, (int)$m[1]);
    }
}

$cfg = Config::load($root);
$pdo = Database::conn($cfg);
$now = (int)(microtime(true) * 1000);
$windowEnd = $now + ($days * 86400000);

$stmt = $pdo->prepare(
    "SELECT * FROM users
     WHERE plan = 'trial'
       AND is_enabled = 1
       AND expires_at IS NOT NULL
       AND expires_at > ?
       AND expires_at <= ?"
);
$stmt->execute([$now, $windowEnd]);

$n = 0;
foreach ($stmt as $user) {
    $uid = (int)$user['id'];
    $left = (int)ceil(((int)$user['expires_at'] - $now) / 86400000);
    $title = '试用即将到期';
    $body = "您的试用还剩约 {$left} 天，请联系管理员开通正式版，以免进入只读或无法登录。";

    $chk = $pdo->prepare(
        "SELECT id FROM messages
         WHERE user_id = ? AND type = 'account.trial_expiring' AND created_at > ?
         LIMIT 1"
    );
    $chk->execute([$uid, $now - 20 * 3600 * 1000]);
    if ($chk->fetch()) {
        continue;
    }

    MessageService::create($pdo, $uid, $title, $body, 'account.trial_expiring');
    $push = PushService::sendToUser($pdo, $cfg, $uid, $title, $body);
    $n++;
    echo "notified user #{$uid} ({$user['username']}) days_left={$left} push_sent={$push['sent']}\n";
}

echo "done, notified={$n}\n";
