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

    public static function login(string $password, array $cfg): bool
    {
        self::startSession();
        if ($password !== ($cfg['admin_password'] ?? '')) {
            return false;
        }
        $_SESSION['truck_ledger_admin'] = true;
        return true;
    }

    public static function logout(): void
    {
        self::startSession();
        unset($_SESSION['truck_ledger_admin']);
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
        return [
            'user_count' => $userCount,
            'round_count' => $roundCount,
            'attachment_count' => $attachmentCount,
            'data_size_mb' => round($dataSize / (1024 * 1024), 2),
        ];
    }

    public static function listUsers(PDO $pdo, array $cfg): array
    {
        $users = [];
        $stmt = $pdo->query(
            'SELECT u.id, u.username, u.license_plate, u.created_at, l.data_json, l.updated_at
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
            $users[] = [
                'id' => (int)$row['id'],
                'username' => $row['username'],
                'license_plate' => (string)($row['license_plate'] ?? ''),
                'created_at' => self::fmtMs((int)$row['created_at']),
                'round_count' => $roundCount,
                'attachment_count' => $attCount,
                'updated_at' => self::fmtMs((int)($row['updated_at'] ?? 0)),
            ];
        }
        return $users;
    }

    public static function getUser(PDO $pdo, int $userId): ?array
    {
        $stmt = $pdo->prepare('SELECT id, username, license_plate, created_at FROM users WHERE id = ?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        return [
            'id' => (int)$row['id'],
            'username' => $row['username'],
            'license_plate' => (string)($row['license_plate'] ?? ''),
            'created_at' => self::fmtMs((int)$row['created_at']),
        ];
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
        return LedgerService::put($pdo, $userId, $body);
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
        $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);
        $dir = $cfg['attachments_dir'] . '/' . $userId;
        if (is_dir($dir)) {
            self::rmTree($dir);
        }
        return $username;
    }

    private static function fmtMs(int $ms): string
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
