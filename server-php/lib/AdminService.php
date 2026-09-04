<?php
declare(strict_types=1);

final class AdminService
{
    public static function startSession(): void
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            session_start();
        }
    }

    public static function isLoggedIn(): bool
    {
        self::startSession();
        return !empty($_SESSION['truck_ledger_admin']);
    }

    public static function verifyPassword(string $password, array $cfg): bool
    {
        $hash = (string)($cfg['admin_password_hash'] ?? '');
        if ($hash !== '') {
            return password_verify($password, $hash);
        }
        $plain = (string)($cfg['admin_password'] ?? '');
        if ($plain !== '' && str_starts_with($plain, '$2y$')) {
            return password_verify($password, $plain);
        }
        if ($plain === '') {
            return false;
        }
        return hash_equals($plain, $password);
    }

    public static function login(string $password, array $cfg): bool
    {
        self::startSession();
        if (!self::verifyPassword($password, $cfg)) {
            return false;
        }
        $_SESSION['truck_ledger_admin'] = true;
        $_SESSION['truck_ledger_admin_csrf'] = bin2hex(random_bytes(16));
        return true;
    }

    public static function csrfToken(): string
    {
        self::startSession();
        if (empty($_SESSION['truck_ledger_admin_csrf'])) {
            $_SESSION['truck_ledger_admin_csrf'] = bin2hex(random_bytes(16));
        }
        return (string)$_SESSION['truck_ledger_admin_csrf'];
    }

    public static function assertCsrf(?string $token): void
    {
        self::startSession();
        $expected = (string)($_SESSION['truck_ledger_admin_csrf'] ?? '');
        if ($expected === '' || $token === null || !hash_equals($expected, $token)) {
            http_response_code(403);
            echo 'CSRF 校验失败';
            exit;
        }
    }

    public static function logout(): void
    {
        self::startSession();
        unset($_SESSION['truck_ledger_admin'], $_SESSION['truck_ledger_admin_csrf']);
    }

    public static function requireLogin(): void
    {
        if (!self::isLoggedIn()) {
            header('Location: /admin/login');
            exit;
        }
    }

    public static function requireLoginJson(): void
    {
        if (!self::isLoggedIn()) {
            JsonResponse::error('未登录管理后台', 401);
        }
    }

    public static function health(PDO $pdo, array $cfg): array
    {
        $checks = [];
        $ok = true;
        try {
            $pdo->query('SELECT 1');
            $checks['database'] = 'ok';
        } catch (Throwable $e) {
            $checks['database'] = 'fail';
            $ok = false;
        }
        $dataDir = $cfg['data_dir'];
        $checks['data_dir_writable'] = is_dir($dataDir) && is_writable($dataDir) ? 'ok' : 'fail';
        if ($checks['data_dir_writable'] !== 'ok') {
            $ok = false;
        }
        $att = $cfg['attachments_dir'];
        $checks['attachments_writable'] = is_dir($att) && is_writable($att) ? 'ok' : 'fail';
        if ($checks['attachments_writable'] !== 'ok') {
            $ok = false;
        }
        $secret = (string)($cfg['jwt_secret'] ?? '');
        $checks['jwt_secret'] = (strlen($secret) >= 16 && $secret !== '请改成至少32位随机字符串') ? 'ok' : 'weak';
        if ($checks['jwt_secret'] !== 'ok') {
            $ok = false;
        }
        $adminHash = (string)($cfg['admin_password_hash'] ?? '');
        $adminPlain = (string)($cfg['admin_password'] ?? '');
        $checks['admin_password'] = ($adminHash !== '' || ($adminPlain !== '' && $adminPlain !== '请改成强密码'))
            ? 'ok' : 'weak';
        $checks['fcm'] = !empty($cfg['fcm_server_key']) ? 'configured' : 'optional';
        $checks['user_count'] = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
        return [
            'status' => $ok ? 'ok' : 'degraded',
            'checks' => $checks,
            'time' => gmdate('c'),
        ];
    }

    public static function stats(PDO $pdo, array $cfg): array
    {
        $userCount = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
        $roundCount = 0;
        foreach ($pdo->query('SELECT data_json FROM ledgers') as $row) {
            $data = json_decode($row['data_json'], true);
            if (is_array($data) && isset($data['rounds']) && is_array($data['rounds'])) {
                $roundCount += count($data['rounds']);
            }
        }
        $attachmentCount = 0;
        $dataSize = 0;
        $root = $cfg['data_dir'];
        if (is_dir($root)) {
            $it = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
            );
            foreach ($it as $file) {
                if ($file->isFile()) {
                    $dataSize += $file->getSize();
                    if (strtolower(substr($file->getFilename(), -4)) === '.jpg') {
                        $attachmentCount++;
                    }
                }
            }
        }
        $unreadDevices = (int)$pdo->query('SELECT COUNT(*) FROM devices')->fetchColumn();
        $msgCount = (int)$pdo->query('SELECT COUNT(*) FROM messages')->fetchColumn();
        return [
            'user_count' => $userCount,
            'round_count' => $roundCount,
            'attachment_count' => $attachmentCount,
            'data_size_mb' => round($dataSize / (1024 * 1024), 2),
            'device_count' => $unreadDevices,
            'message_count' => $msgCount,
        ];
    }

    public static function listUsers(PDO $pdo, array $cfg): array
    {
        $users = [];
        $stmt = $pdo->query(
            'SELECT u.id, u.username, u.license_plate, u.is_enabled, u.status, u.plan, u.expires_at,
                    u.created_at, l.data_json, l.updated_at, l.revision
             FROM users u LEFT JOIN ledgers l ON l.user_id = u.id ORDER BY u.id'
        );
        foreach ($stmt as $row) {
            $roundCount = 0;
            if (!empty($row['data_json'])) {
                $data = json_decode($row['data_json'], true);
                if (is_array($data) && isset($data['rounds'])) {
                    $roundCount = count($data['rounds']);
                }
            }
            $userDir = $cfg['attachments_dir'] . '/' . $row['id'];
            $attCount = 0;
            if (is_dir($userDir)) {
                $attCount = count(glob($userDir . '/*.jpg') ?: []);
            }
            $profile = EntitlementService::publicProfile($pdo, $row);
            $users[] = [
                'id' => (int)$row['id'],
                'username' => $row['username'],
                'license_plate' => (string)($row['license_plate'] ?? ''),
                'is_enabled' => (int)($row['is_enabled'] ?? 1) === 1,
                'status' => $profile['status'],
                'plan' => $profile['plan'],
                'expires_at' => $profile['expires_at'],
                'days_left' => $profile['days_left'],
                'write_allowed' => $profile['write_allowed'],
                'created_at' => self::fmtMs((int)$row['created_at']),
                'round_count' => $roundCount,
                'attachment_count' => $attCount,
                'revision' => (int)($row['revision'] ?? 0),
                'updated_at' => self::fmtMs((int)($row['updated_at'] ?? 0)),
            ];
        }
        return $users;
    }

    public static function getUser(PDO $pdo, int $userId): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $profile = EntitlementService::publicProfile($pdo, $row);
        return array_merge($profile, [
            'created_at' => self::fmtMs((int)$row['created_at']),
        ]);
    }

    /** @return string|null 成功返回提示文案，用户不存在返回 null */
    public static function setUserEnabled(PDO $pdo, int $userId, bool $enabled): ?string
    {
        $stmt = $pdo->prepare('SELECT username, status, plan FROM users WHERE id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $status = $enabled ? 'ACTIVE' : 'SUSPENDED';
        $pdo->prepare(
            'UPDATE users SET is_enabled=?, status=?, token_version=token_version+1 WHERE id=?'
        )->execute([$enabled ? 1 : 0, $status, $userId]);
        AppControlService::audit($pdo, null, 'USER_ENABLE_TOGGLE', 'user', (string)$userId, [
            'enabled' => $enabled,
            'before' => $row['status'],
        ]);
        $name = $row['username'];
        return $enabled ? "已允许用户 {$name} 使用" : "已禁止用户 {$name} 使用";
    }

    public static function extendTrial(PDO $pdo, int $userId, int $days): ?string
    {
        $stmt = $pdo->prepare('SELECT * FROM users WHERE id=?');
        $stmt->execute([$userId]);
        $u = $stmt->fetch();
        if (!$u) {
            return null;
        }
        $now = (int)(microtime(true) * 1000);
        $base = max($now, (int)($u['expires_at'] ?? 0));
        $expires = $base + ($days * 86400000);
        AppControlService::setUserEntitlement($pdo, $userId, 'ACTIVE', 'trial', $expires, false, null);
        return "已为 {$u['username']} 延期试用 {$days} 天";
    }

    public static function convertPaid(PDO $pdo, int $userId): ?string
    {
        $stmt = $pdo->prepare('SELECT username FROM users WHERE id=?');
        $stmt->execute([$userId]);
        $u = $stmt->fetch();
        if (!$u) {
            return null;
        }
        AppControlService::setUserEntitlement($pdo, $userId, 'ACTIVE', 'paid', null, false, null);
        return "已将 {$u['username']} 转为正式用户";
    }

    public static function getUserLedger(PDO $pdo, int $userId): ?array
    {
        if (self::getUser($pdo, $userId) === null) {
            return null;
        }
        return LedgerService::get($pdo, $userId);
    }

    public static function putUserLedger(PDO $pdo, int $userId, array $body): ?array
    {
        if (self::getUser($pdo, $userId) === null) {
            return null;
        }
        return LedgerService::put($pdo, $userId, $body, null, !empty($body['force']) || !array_key_exists('base_revision', $body), true);
    }

    public static function deleteUser(PDO $pdo, array $cfg, int $userId): ?string
    {
        $stmt = $pdo->prepare('SELECT username FROM users WHERE id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $username = $row['username'];
        $pdo->prepare('DELETE FROM ledgers WHERE user_id = ?')->execute([$userId]);
        $pdo->prepare('DELETE FROM devices WHERE user_id = ?')->execute([$userId]);
        $pdo->prepare('DELETE FROM push_tokens WHERE user_id = ?')->execute([$userId]);
        $pdo->prepare('DELETE FROM ledger_snapshots WHERE user_id = ?')->execute([$userId]);
        $pdo->prepare('DELETE FROM message_reads WHERE user_id = ?')->execute([$userId]);
        $pdo->prepare('DELETE FROM messages WHERE user_id = ?')->execute([$userId]);
        $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);
        $dir = $cfg['attachments_dir'] . '/' . $userId;
        if (is_dir($dir)) {
            self::rmTree($dir);
        }
        AppControlService::audit($pdo, null, 'USER_DELETE', 'user', (string)$userId, ['username' => $username]);
        return $username;
    }

    public static function fmtMs(int $ms): string
    {
        if ($ms <= 0) {
            return '—';
        }
        return date('Y-m-d H:i', (int)($ms / 1000));
    }

    private static function rmTree(string $dir): void
    {
        foreach (glob($dir . '/*') ?: [] as $item) {
            is_dir($item) ? self::rmTree($item) : unlink($item);
        }
        rmdir($dir);
    }
}
