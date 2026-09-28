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
        $sa = self::loadServiceAccount($cfg);
        if ($sa === null) {
            return [
                'ok' => false,
                'configured' => false,
                'mode' => 'none',
                'detail' => '未配置 fcm_service_account_file（或文件无效）',
            ];
        }
        $projectId = self::projectId($cfg, $sa);
        return [
            'ok' => true,
            'configured' => true,
            'mode' => 'http_v1',
            'detail' => 'project=' . $projectId,
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
            $tokens[] = $row['token'];
        }
        if ($tokens === []) {
            return ['sent' => 0, 'skipped' => 1, 'errors' => []];
        }

        $sa = self::loadServiceAccount($cfg);
        if ($sa === null) {
            return [
                'sent' => 0,
                'skipped' => count($tokens),
                'errors' => ['未配置 FCM 服务账号（fcm_service_account_file）'],
            ];
        }

        $access = self::accessToken($cfg, $sa);
        if ($access === null) {
            return [
                'sent' => 0,
                'skipped' => 0,
                'errors' => ['无法获取 FCM OAuth access token'],
            ];
        }

        $projectId = self::projectId($cfg, $sa);
        $sent = 0;
        $errors = [];
        $skipped = 0;
        foreach ($tokens as $token) {
            if (str_starts_with($token, 'local:')) {
                $skipped++;
                continue;
            }
            $ok = self::fcmHttpV1Send($projectId, $access, $token, $title, $body, $data);
            if ($ok === true) {
                $sent++;
            } else {
                $errors[] = (string)$ok;
            }
        }
        return ['sent' => $sent, 'skipped' => $skipped, 'errors' => $errors];
    }

    /** @return array<string,mixed>|null */
    private static function loadServiceAccount(array $cfg): ?array
    {
        $path = trim((string)($cfg['fcm_service_account_file'] ?? ''));
        if ($path === '') {
            // 默认路径：站点根 data/fcm-service-account.json
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

    /**
     * @param array<string,mixed> $sa
     */
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
