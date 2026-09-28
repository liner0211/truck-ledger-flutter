<?php
declare(strict_types=1);

/**
 * 向本机 WebSocket 枢纽发布事件（不用 FCM）。
 * 失败时静默忽略，不影响主 API。
 */
final class RealtimeHub
{
    public static function internalToken(array $cfg): string
    {
        $t = trim((string)($cfg['ws_internal_token'] ?? ''));
        if ($t !== '') {
            return $t;
        }
        return hash('sha256', (string)($cfg['jwt_secret'] ?? '') . '|ws-internal');
    }

    public static function publishUrl(array $cfg): string
    {
        $url = trim((string)($cfg['ws_publish_url'] ?? ''));
        if ($url !== '') {
            return $url;
        }
        $port = (int)($cfg['ws_port'] ?? 8765);
        return 'http://127.0.0.1:' . $port . '/publish';
    }

    public static function enabled(array $cfg): bool
    {
        if (array_key_exists('ws_enabled', $cfg)) {
            return (bool)$cfg['ws_enabled'];
        }
        return true;
    }

    /**
     * @param list<array{role:string,id?:int|null}> $targets
     * @param array<string,mixed> $payload
     */
    public static function publish(array $cfg, array $targets, array $payload): void
    {
        if (!self::enabled($cfg)) {
            return;
        }
        $url = self::publishUrl($cfg);
        $body = json_encode(
            ['targets' => $targets, 'payload' => $payload],
            JSON_UNESCAPED_UNICODE
        );
        if ($body === false) {
            return;
        }
        $token = self::internalToken($cfg);

        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            if ($ch === false) {
                return;
            }
            curl_setopt_array($ch, [
                CURLOPT_POST => true,
                CURLOPT_HTTPHEADER => [
                    'Content-Type: application/json',
                    'X-Internal-Token: ' . $token,
                ],
                CURLOPT_POSTFIELDS => $body,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_CONNECTTIMEOUT => 1,
                CURLOPT_TIMEOUT => 2,
            ]);
            curl_exec($ch);
            curl_close($ch);
            return;
        }

        $ctx = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => "Content-Type: application/json\r\nX-Internal-Token: {$token}\r\n",
                'content' => $body,
                'timeout' => 2,
                'ignore_errors' => true,
            ],
        ]);
        @file_get_contents($url, false, $ctx);
    }

    /** 站内信变更：通知目标用户 + 全体管理员。 */
    public static function inboxUpdated(array $cfg, ?int $userId, string $event, array $extra = []): void
    {
        $targets = [['role' => 'admin']];
        if ($userId !== null && $userId > 0) {
            $targets[] = ['role' => 'user', 'id' => $userId];
        } else {
            $targets[] = ['role' => 'user']; // 广播
        }
        self::publish($cfg, $targets, array_merge([
            'type' => 'inbox',
            'event' => $event,
            'user_id' => $userId,
        ], $extra));
    }

    /** 客服会话：通知该用户 + 全体管理员。 */
    public static function supportUpdated(array $cfg, int $userId, int $threadId, string $event, array $extra = []): void
    {
        self::publish($cfg, [
            ['role' => 'user', 'id' => $userId],
            ['role' => 'admin'],
        ], array_merge([
            'type' => 'support',
            'event' => $event,
            'user_id' => $userId,
            'thread_id' => $threadId,
        ], $extra));
    }

    /**
     * 私聊/群聊：通知会话内全体用户 + 全体管理员（监管）。
     * @param list<int> $memberUserIds
     */
    public static function chatUpdated(
        array $cfg,
        int $conversationId,
        array $memberUserIds,
        string $event,
        array $extra = []
    ): void {
        $targets = [['role' => 'admin']];
        foreach ($memberUserIds as $uid) {
            $uid = (int)$uid;
            if ($uid > 0) {
                $targets[] = ['role' => 'user', 'id' => $uid];
            }
        }
        self::publish($cfg, $targets, array_merge([
            'type' => 'chat',
            'event' => $event,
            'conversation_id' => $conversationId,
        ], $extra));
    }

    /**
     * 探测本机 WS 枢纽健康（供管理端/网页展示）。
     * @return array{ok:bool,reachable:bool,clients?:int,admins?:int,users?:int,error?:string,publish_url:string,port:int}
     */
    public static function status(array $cfg): array
    {
        $port = (int)($cfg['ws_port'] ?? 8765);
        $base = [
            'ok' => false,
            'reachable' => false,
            'publish_url' => self::publishUrl($cfg),
            'port' => $port,
            'enabled' => self::enabled($cfg),
        ];
        if (!self::enabled($cfg)) {
            $base['error'] = 'disabled';
            return $base;
        }
        $url = 'http://127.0.0.1:' . $port . '/health';
        $raw = null;
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            if ($ch !== false) {
                curl_setopt_array($ch, [
                    CURLOPT_RETURNTRANSFER => true,
                    CURLOPT_CONNECTTIMEOUT => 1,
                    CURLOPT_TIMEOUT => 2,
                ]);
                $raw = curl_exec($ch);
                curl_close($ch);
            }
        } else {
            $ctx = stream_context_create(['http' => ['timeout' => 2, 'ignore_errors' => true]]);
            $raw = @file_get_contents($url, false, $ctx);
        }
        if (!is_string($raw) || $raw === '') {
            $base['error'] = 'unreachable';
            return $base;
        }
        $j = json_decode($raw, true);
        if (!is_array($j) || empty($j['ok'])) {
            $base['error'] = 'bad_response';
            return $base;
        }
        return array_merge($base, [
            'ok' => true,
            'reachable' => true,
            'clients' => (int)($j['clients'] ?? 0),
            'admins' => (int)($j['admins'] ?? 0),
            'users' => (int)($j['users'] ?? 0),
        ]);
    }
}
