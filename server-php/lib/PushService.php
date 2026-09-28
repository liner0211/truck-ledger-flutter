<?php
declare(strict_types=1);

/**
 * 推送 Token 登记 + 极光推送（国内主通道）。
 * 未配置极光时仍可靠站内信 + WebSocket + 客户端本地通知栏。
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

    /** @return array{ok:bool,configured:bool,mode:string,detail?:string} */
    public static function status(array $cfg): array
    {
        $jKey = trim((string)($cfg['jpush_app_key'] ?? ''));
        $jSec = trim((string)($cfg['jpush_master_secret'] ?? ''));
        if ($jKey !== '' && $jSec !== '') {
            return [
                'ok' => true,
                'configured' => true,
                'mode' => 'jpush',
                'detail' => 'jpush_app_key=' . substr($jKey, 0, 8) . '…',
            ];
        }
        return [
            'ok' => false,
            'configured' => false,
            'mode' => 'none',
            'detail' => '未配置极光(jpush_*)；在线仍可靠 WS+本地通知栏',
        ];
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
        $stmt = $pdo->prepare('SELECT token FROM push_tokens WHERE user_id=?');
        $stmt->execute([$userId]);
        $tokens = [];
        foreach ($stmt as $row) {
            $tokens[] = (string)$row['token'];
        }
        if ($tokens === []) {
            return ['sent' => 0, 'skipped' => 1, 'errors' => []];
        }

        $sent = 0;
        $errors = [];
        $skipped = 0;
        $jpushIds = [];

        foreach ($tokens as $token) {
            if (str_starts_with($token, 'local:')) {
                $skipped++;
                continue;
            }
            if (str_starts_with($token, 'jpush:')) {
                $rid = substr($token, 6);
                if ($rid !== '') {
                    $jpushIds[] = $rid;
                } else {
                    $skipped++;
                }
                continue;
            }
            // 历史 FCM 等非极光 token：跳过
            $skipped++;
        }

        if ($jpushIds !== []) {
            $r = self::jpushSend($cfg, $jpushIds, $title, $body, $data);
            $sent += $r['sent'];
            $errors = array_merge($errors, $r['errors']);
            $skipped += $r['skipped'];
        }

        if ($sent === 0 && $skipped === count($tokens) && $errors === []) {
            $errors[] = '无可用极光 token，无法发系统推送（在线仍可靠 WS+本地通知）';
        }

        return ['sent' => $sent, 'skipped' => $skipped, 'errors' => $errors];
    }

    /**
     * 极光推送 REST API。
     * @param list<string> $registrationIds
     * @return array{sent:int, skipped:int, errors:string[]}
     */
    private static function jpushSend(
        array $cfg,
        array $registrationIds,
        string $title,
        string $body,
        array $data = []
    ): array {
        $appKey = trim((string)($cfg['jpush_app_key'] ?? ''));
        $secret = trim((string)($cfg['jpush_master_secret'] ?? ''));
        if ($appKey === '' || $secret === '') {
            return [
                'sent' => 0,
                'skipped' => count($registrationIds),
                'errors' => ['未配置 jpush_app_key / jpush_master_secret'],
            ];
        }
        if (!function_exists('curl_init')) {
            return ['sent' => 0, 'skipped' => 0, 'errors' => ['PHP curl 扩展不可用']];
        }

        $extras = [];
        foreach (array_merge(['type' => 'inbox'], $data) as $k => $v) {
            $extras[(string)$k] = (string)$v;
        }
        if (!isset($extras['payload'])) {
            $type = $extras['type'] ?? 'inbox';
            if ($type === 'chat' && !empty($extras['conversation_id'])) {
                $extras['payload'] = 'chat:' . $extras['conversation_id'];
            } elseif ($type === 'support') {
                $extras['payload'] = 'support';
            } elseif ($type === 'inbox' && !empty($extras['message_id'])) {
                $extras['payload'] = 'inbox:' . $extras['message_id'];
            } else {
                $extras['payload'] = 'hub:0';
            }
        }

        $payload = [
            'platform' => 'all',
            'audience' => ['registration_id' => array_values(array_unique($registrationIds))],
            'notification' => [
                'alert' => $body !== '' ? $body : $title,
                'android' => [
                    'title' => $title,
                    'alert' => $body !== '' ? $body : $title,
                    'extras' => $extras,
                ],
                'ios' => [
                    'alert' => [
                        'title' => $title,
                        'body' => $body !== '' ? $body : $title,
                    ],
                    'sound' => 'default',
                    'badge' => '+1',
                    'extras' => $extras,
                ],
            ],
            'options' => [
                'apns_production' => !empty($cfg['jpush_apns_production']),
            ],
        ];

        $ch = curl_init('https://api.jpush.cn/v3/push');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Authorization: Basic ' . base64_encode($appKey . ':' . $secret),
            ],
            CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
        ]);
        $resp = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($resp === false) {
            return ['sent' => 0, 'skipped' => 0, 'errors' => [$err ?: 'jpush curl 失败']];
        }
        if ($code < 200 || $code >= 300) {
            return ['sent' => 0, 'skipped' => 0, 'errors' => ["JPush HTTP {$code}: {$resp}"]];
        }
        return ['sent' => count($registrationIds), 'skipped' => 0, 'errors' => []];
    }
}
