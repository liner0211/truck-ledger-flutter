<?php
declare(strict_types=1);

/**
 * 推送 Token 登记 + FCM HTTP v1（服务账号 JSON）。
 * Legacy Server Key 已停用；未配置服务账号时仍可靠站内信 + WebSocket。
 */
final class PushService
{
    private static ?array $tokenCache = null;

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
        $sa = self::loadServiceAccount($cfg);
        if ($sa === null) {
            return [
                'ok' => false,
                'configured' => false,
                'mode' => 'none',
                'detail' => '未配置极光(jpush_*) 或 FCM；在线仍可靠 WS+本地通知栏',
            ];
        }
        return [
            'ok' => true,
            'configured' => true,
            'mode' => 'http_v1',
            'detail' => 'project=' . self::projectId($cfg, $sa),
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
        $fcmTokens = [];

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
            $fcmTokens[] = $token;
        }

        if ($jpushIds !== []) {
            $r = self::jpushSend($cfg, $jpushIds, $title, $body, $data);
            $sent += $r['sent'];
            $errors = array_merge($errors, $r['errors']);
            $skipped += $r['skipped'];
        }

        if ($fcmTokens !== []) {
            $sa = self::loadServiceAccount($cfg);
            if ($sa === null) {
                $skipped += count($fcmTokens);
                $errors[] = '未配置 FCM 服务账号，已跳过 FCM token';
            } else {
                $access = self::accessToken($cfg, $sa);
                if ($access === null) {
                    $errors[] = '无法获取 FCM OAuth access token';
                } else {
                    $projectId = self::projectId($cfg, $sa);
                    foreach ($fcmTokens as $token) {
                        $ok = self::fcmHttpV1Send($projectId, $access, $token, $title, $body, $data);
                        if ($ok === true) {
                            $sent++;
                        } else {
                            $errors[] = (string)$ok;
                        }
                    }
                }
            }
        }

        if ($sent === 0 && $skipped === count($tokens) && $errors === []) {
            $errors[] = '仅有 local 占位 token，无法发系统推送（需极光或 FCM）';
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
        // 客户端 LocalPushService / ChinaPush 用 payload 跳转
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

    /** @return array<string,mixed>|null */
    private static function loadServiceAccount(array $cfg): ?array
    {
        $path = trim((string)($cfg['fcm_service_account_file'] ?? ''));
        if ($path === '') {
            $root = dirname(__DIR__);
            $path = $root . '/data/fcm-service-account.json';
        } elseif ($path[0] !== '/') {
            $path = dirname(__DIR__) . '/' . ltrim($path, '/');
        }
        if (!is_file($path) || !is_readable($path)) {
            return null;
        }
        $raw = file_get_contents($path);
        if ($raw === false || $raw === '') {
            return null;
        }
        $json = json_decode($raw, true);
        if (!is_array($json)) {
            return null;
        }
        if (empty($json['client_email']) || empty($json['private_key']) || empty($json['project_id'])) {
            return null;
        }
        return $json;
    }

    /** @param array<string,mixed> $sa */
    private static function projectId(array $cfg, array $sa): string
    {
        $override = trim((string)($cfg['fcm_project_id'] ?? ''));
        if ($override !== '') {
            return $override;
        }
        return (string)$sa['project_id'];
    }

    /** @param array<string,mixed> $sa */
    private static function accessToken(array $cfg, array $sa): ?string
    {
        $now = time();
        if (self::$tokenCache !== null
            && (int)(self::$tokenCache['exp'] ?? 0) > $now + 60
            && !empty(self::$tokenCache['access_token'])
        ) {
            return (string)self::$tokenCache['access_token'];
        }

        $cacheFile = dirname(__DIR__) . '/data/fcm_access_token.json';
        if (is_file($cacheFile)) {
            $cached = json_decode((string)file_get_contents($cacheFile), true);
            if (is_array($cached)
                && (int)($cached['exp'] ?? 0) > $now + 60
                && !empty($cached['access_token'])
            ) {
                self::$tokenCache = $cached;
                return (string)$cached['access_token'];
            }
        }

        $jwt = self::makeServiceJwt($sa);
        if ($jwt === null) {
            return null;
        }
        if (!function_exists('curl_init')) {
            return null;
        }
        $ch = curl_init('https://oauth2.googleapis.com/token');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
            CURLOPT_POSTFIELDS => http_build_query([
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ]),
        ]);
        $resp = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($resp === false || $code < 200 || $code >= 300) {
            return null;
        }
        $body = json_decode($resp, true);
        if (!is_array($body) || empty($body['access_token'])) {
            return null;
        }
        $entry = [
            'access_token' => (string)$body['access_token'],
            'exp' => $now + (int)($body['expires_in'] ?? 3600),
        ];
        self::$tokenCache = $entry;
        @file_put_contents($cacheFile, json_encode($entry), LOCK_EX);
        @chmod($cacheFile, 0600);
        return (string)$entry['access_token'];
    }

    /** @param array<string,mixed> $sa */
    private static function makeServiceJwt(array $sa): ?string
    {
        $now = time();
        $header = self::b64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'], JSON_UNESCAPED_SLASHES));
        $claims = self::b64url(json_encode([
            'iss' => (string)$sa['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => 'https://oauth2.googleapis.com/token',
            'iat' => $now,
            'exp' => $now + 3600,
        ], JSON_UNESCAPED_SLASHES));
        $unsigned = $header . '.' . $claims;
        $key = openssl_pkey_get_private((string)$sa['private_key']);
        if ($key === false) {
            return null;
        }
        $sig = '';
        $ok = openssl_sign($unsigned, $sig, $key, OPENSSL_ALGO_SHA256);
        if (!$ok) {
            return null;
        }
        return $unsigned . '.' . self::b64url($sig);
    }

    private static function b64url(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    /** @return true|string */
    private static function fcmHttpV1Send(
        string $projectId,
        string $accessToken,
        string $deviceToken,
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
        foreach ($dataOut as $k => $v) {
            $dataOut[$k] = (string)$v;
        }
        $payload = json_encode([
            'message' => [
                'token' => $deviceToken,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $dataOut,
                'android' => [
                    'priority' => 'HIGH',
                    'notification' => [
                        'channel_id' => 'messages',
                        'sound' => 'default',
                    ],
                ],
                'apns' => [
                    'payload' => [
                        'aps' => [
                            'sound' => 'default',
                            'badge' => 1,
                        ],
                    ],
                ],
            ],
        ], JSON_UNESCAPED_UNICODE);

        $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($projectId) . '/messages:send';
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $accessToken,
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
            return "FCM v1 HTTP {$code}: {$resp}";
        }
        return true;
    }
}
