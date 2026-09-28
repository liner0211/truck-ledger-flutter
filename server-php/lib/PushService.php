<?php
declare(strict_types=1);

/**
 * 推送 Token 登记 + 可选 FCM HTTP v1（需配置 fcm_server_key）。
 * 未配置 FCM 时仍可通过站内信触达。
 */
final class PushService
{
    public static function upsertToken(
        PDO $pdo,
        int $userId,
        string $deviceId,
        string $token,
        string $platform
    ): void {
        $deviceId = trim($deviceId);
        $token = trim($token);
        if ($deviceId === '' || $token === '' || strlen($deviceId) > 128) {
            JsonResponse::error('推送参数无效', 400);
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            'INSERT INTO push_tokens (user_id, device_id, token, platform, updated_at) VALUES (?,?,?,?,?)
             ON CONFLICT(user_id, device_id) DO UPDATE SET
               token=excluded.token, platform=excluded.platform, updated_at=excluded.updated_at'
        )->execute([$userId, $deviceId, $token, strtolower($platform), $now]);
    }

    public static function removeToken(PDO $pdo, int $userId, string $deviceId): void
    {
        $pdo->prepare('DELETE FROM push_tokens WHERE user_id=? AND device_id=?')
            ->execute([$userId, trim($deviceId)]);
    }

    /** @return array{sent:int, skipped:int, errors:string[]} */
    public static function notifyUser(PDO $pdo, array $cfg, int $userId, string $title, string $body): array
    {
        $mid = MessageService::create($pdo, $userId, $title, $body, 'account.notify');
        RealtimeHub::inboxUpdated($cfg, $userId, 'created', [
            'message_id' => $mid,
            'title' => $title,
            'preview' => mb_substr($body, 0, 80),
        ]);
        return self::sendToUser($pdo, $cfg, $userId, $title, $body);
    }

    /** @return array{sent:int, skipped:int, errors:string[]} */
    public static function broadcast(PDO $pdo, array $cfg, string $title, string $body, string $type = 'ops.broadcast'): array
    {
        $mid = MessageService::create($pdo, null, $title, $body, $type);
        RealtimeHub::inboxUpdated($cfg, null, 'created', [
            'message_id' => $mid,
            'title' => $title,
            'preview' => mb_substr($body, 0, 80),
        ]);
        $sent = 0;
        $skipped = 0;
        $errors = [];
        foreach ($pdo->query('SELECT DISTINCT user_id FROM push_tokens') as $row) {
            $r = self::sendToUser($pdo, $cfg, (int)$row['user_id'], $title, $body);
            $sent += $r['sent'];
            $skipped += $r['skipped'];
            $errors = array_merge($errors, $r['errors']);
        }
        return ['sent' => $sent, 'skipped' => $skipped, 'errors' => $errors];
    }

    /** @return array{sent:int, skipped:int, errors:string[]} */
    public static function sendToUser(
        PDO $pdo,
        array $cfg,
        int $userId,
        string $title,
        string $body,
        array $data = []
    ): array {
        $key = (string)($cfg['fcm_server_key'] ?? '');
        $stmt = $pdo->prepare('SELECT token FROM push_tokens WHERE user_id=?');
        $stmt->execute([$userId]);
        $tokens = [];
        foreach ($stmt as $row) {
            $tokens[] = $row['token'];
        }
        if ($tokens === []) {
            return ['sent' => 0, 'skipped' => 1, 'errors' => []];
        }
        if ($key === '') {
            return ['sent' => 0, 'skipped' => count($tokens), 'errors' => ['未配置 fcm_server_key，已写入站内信']];
        }
        $sent = 0;
        $errors = [];
        $skipped = 0;
        foreach ($tokens as $token) {
            // local: 占位 token 非 FCM，跳过
            if (str_starts_with($token, 'local:')) {
                $skipped++;
                continue;
            }
            $ok = self::fcmLegacySend($key, $token, $title, $body, $data);
            if ($ok === true) {
                $sent++;
            } else {
                $errors[] = (string)$ok;
            }
        }
        return ['sent' => $sent, 'skipped' => $skipped, 'errors' => $errors];
    }

    /** @return true|string */
    private static function fcmLegacySend(
        string $serverKey,
        string $token,
        string $title,
        string $body,
        array $data = []
    ) {
        if (!function_exists('curl_init')) {
            return 'PHP curl 扩展不可用';
        }
        $dataOut = array_merge([
            'title' => $title,
            'body' => $body,
            'type' => 'inbox',
        ], $data);
        // FCM data 值须为字符串
        foreach ($dataOut as $k => $v) {
            $dataOut[$k] = (string)$v;
        }
        $payload = json_encode([
            'to' => $token,
            'notification' => [
                'title' => $title,
                'body' => $body,
                'android_channel_id' => 'messages',
            ],
            'data' => $dataOut,
            'priority' => 'high',
            'content_available' => true,
            'android' => [
                'priority' => 'high',
                'notification' => [
                    'channel_id' => 'messages',
                    'sound' => 'default',
                ],
            ],
        ], JSON_UNESCAPED_UNICODE);
        $ch = curl_init('https://fcm.googleapis.com/fcm/send');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: key=' . $serverKey,
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
        ]);
        $resp = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($resp === false) {
            return $err ?: 'curl 失败';
        }
        if ($code < 200 || $code >= 300) {
            return "FCM HTTP {$code}: {$resp}";
        }
        return true;
    }
}
