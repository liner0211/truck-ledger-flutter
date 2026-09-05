<?php
declare(strict_types=1);

/**
 * 管理员身份：Web Session + Flutter Admin JWT（typ=admin）。
 * role:
 *   - super    = 开发者/维护者（底层控制面、运营账号、删用户、设备/快照等）
 *   - operator = 会计管理员（用户与账本业务数据，不可动底层配置）
 */
final class AdminAuthService
{
    public const ROLE_SUPER = 'super';
    public const ROLE_OPERATOR = 'operator';

    /** @return list<string> */
    public static function permissionsForRole(string $role): array
    {
        // 会计管理员：业务运营（看改用户/账本、发消息），不含底层维护
        $accountant = [
            'dashboard.read',
            'users.read',
            'users.write',
            'messages.send',
            'ledger.read',
            'ledger.write',
        ];
        if ($role === self::ROLE_SUPER) {
            return array_values(array_unique(array_merge($accountant, [
                'users.delete',
                'control.write',
                'admins.manage',
                'devices.write',
                'snapshots.restore',
            ])));
        }
        return $accountant;
    }

    public static function roleLabel(string $role): string
    {
        return $role === self::ROLE_SUPER ? '开发者' : '会计管理员';
    }

    public static function can(?array $admin, string $permission): bool
    {
        if ($admin === null) {
            return false;
        }
        if ((int)($admin['is_enabled'] ?? 0) !== 1) {
            return false;
        }
        $role = (string)($admin['role'] ?? '');
        return in_array($permission, self::permissionsForRole($role), true);
    }

    public static function requirePermission(?array $admin, string $permission): void
    {
        if (!self::can($admin, $permission)) {
            JsonResponse::error('权限不足', 403);
        }
    }

    public static function publicAdmin(array $row): array
    {
        $role = (string)$row['role'];
        return [
            'id' => (int)$row['id'],
            'username' => (string)$row['username'],
            'role' => $role,
            'role_label' => self::roleLabel($role),
            'is_enabled' => (int)($row['is_enabled'] ?? 1) === 1,
            'permissions' => self::permissionsForRole($role),
            'last_login_at' => isset($row['last_login_at']) ? (int)$row['last_login_at'] : null,
        ];
    }

    public static function findByUsername(PDO $pdo, string $username): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM admins WHERE username=?');
        $stmt->execute([trim($username)]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function findById(PDO $pdo, int $id): ?array
    {
        $stmt = $pdo->prepare('SELECT * FROM admins WHERE id=?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function verifyLogin(PDO $pdo, string $username, string $password): ?array
    {
        $row = self::findByUsername($pdo, $username);
        if (!$row) {
            return null;
        }
        if ((int)($row['is_enabled'] ?? 0) !== 1) {
            return null;
        }
        if (!password_verify($password, (string)$row['password_hash'])) {
            return null;
        }
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare('UPDATE admins SET last_login_at=? WHERE id=?')->execute([$now, $row['id']]);
        $row['last_login_at'] = $now;
        return $row;
    }

    public static function createToken(array $admin, array $cfg): string
    {
        $now = time();
        $expire = (int)($cfg['admin_jwt_expire_sec'] ?? $cfg['jwt_expire_sec'] ?? 86400 * 7);
        return Jwt::encode([
            'typ' => 'admin',
            'sub' => (string)$admin['id'],
            'username' => $admin['username'],
            'role' => $admin['role'],
            'ver' => (int)($admin['token_version'] ?? 0),
            'iat' => $now,
            'exp' => $now + max(3600, $expire),
        ], $cfg['jwt_secret']);
    }

    public static function requireAdminJwt(PDO $pdo, array $cfg): array
    {
        $hdr = (string)($_SERVER['HTTP_AUTHORIZATION'] ?? '');
        if (!preg_match('/Bearer\s+(\S+)/i', $hdr, $m)) {
            JsonResponse::error('未登录', 401);
        }
        $payload = Jwt::decode($m[1], $cfg['jwt_secret']);
        if ($payload === null || ($payload['typ'] ?? '') !== 'admin') {
            JsonResponse::error('管理员登录已失效', 401);
        }
        $id = (int)($payload['sub'] ?? 0);
        $admin = self::findById($pdo, $id);
        if ($admin === null || (int)($admin['is_enabled'] ?? 0) !== 1) {
            JsonResponse::error('管理员账号不可用', 401);
        }
        $ver = (int)($payload['ver'] ?? -1);
        if ($ver !== (int)($admin['token_version'] ?? 0)) {
            JsonResponse::error('管理员登录已失效', 401);
        }
        return $admin;
    }

    /** Web session 当前管理员（可能为 null） */
    public static function currentSessionAdmin(PDO $pdo): ?array
    {
        AdminService::startSession();
        $id = (int)($_SESSION['truck_ledger_admin_id'] ?? 0);
        if ($id <= 0) {
            return null;
        }
        $admin = self::findById($pdo, $id);
        if ($admin === null || (int)($admin['is_enabled'] ?? 0) !== 1) {
            return null;
        }
        return $admin;
    }

    public static function loginSession(array $admin): void
    {
        AdminService::startSession();
        $_SESSION['truck_ledger_admin'] = true;
        $_SESSION['truck_ledger_admin_id'] = (int)$admin['id'];
        $_SESSION['truck_ledger_admin_role'] = (string)$admin['role'];
        $_SESSION['truck_ledger_admin_csrf'] = bin2hex(random_bytes(16));
    }

    public static function listAdmins(PDO $pdo): array
    {
        $out = [];
        foreach ($pdo->query('SELECT * FROM admins ORDER BY id') as $row) {
            $out[] = self::publicAdmin($row);
        }
        return $out;
    }

    public static function createOperator(PDO $pdo, string $username, string $password, ?int $actorId): array
    {
        $u = trim($username);
        if (!preg_match('/^[A-Za-z0-9_]{3,32}$/', $u)) {
            throw new InvalidArgumentException('用户名须为 3–32 位字母数字下划线');
        }
        if (strlen($password) < 6) {
            throw new InvalidArgumentException('密码至少 6 位');
        }
        $hash = password_hash($password, PASSWORD_BCRYPT);
        $now = (int)(microtime(true) * 1000);
        try {
            $pdo->prepare(
                'INSERT INTO admins (username, password_hash, role, is_enabled, token_version, created_at)
                 VALUES (?,?,?,?,0,?)'
            )->execute([$u, $hash, self::ROLE_OPERATOR, 1, $now]);
        } catch (PDOException $e) {
            if (str_contains($e->getMessage(), 'UNIQUE')) {
                throw new InvalidArgumentException('管理员用户名已存在');
            }
            throw $e;
        }
        $id = (int)$pdo->lastInsertId();
        AppControlService::audit($pdo, $actorId, 'ADMIN_CREATE', 'admin', (string)$id, [
            'username' => $u,
            'role' => self::ROLE_OPERATOR,
        ]);
        return self::publicAdmin(self::findById($pdo, $id));
    }

    public static function setEnabled(PDO $pdo, int $adminId, bool $enabled, ?int $actorId): bool
    {
        $row = self::findById($pdo, $adminId);
        if (!$row) {
            return false;
        }
        if ((string)$row['role'] === self::ROLE_SUPER && !$enabled) {
            throw new InvalidArgumentException('不能禁用开发者账号');
        }
        $pdo->prepare(
            'UPDATE admins SET is_enabled=?, token_version=token_version+1 WHERE id=?'
        )->execute([$enabled ? 1 : 0, $adminId]);
        AppControlService::audit($pdo, $actorId, 'ADMIN_ENABLE_TOGGLE', 'admin', (string)$adminId, [
            'enabled' => $enabled,
        ]);
        return true;
    }

    public static function resetPassword(PDO $pdo, int $adminId, string $newPassword, ?int $actorId): bool
    {
        if (strlen($newPassword) < 6) {
            throw new InvalidArgumentException('密码至少 6 位');
        }
        $row = self::findById($pdo, $adminId);
        if (!$row) {
            return false;
        }
        $hash = password_hash($newPassword, PASSWORD_BCRYPT);
        $pdo->prepare(
            'UPDATE admins SET password_hash=?, token_version=token_version+1 WHERE id=?'
        )->execute([$hash, $adminId]);
        AppControlService::audit($pdo, $actorId, 'ADMIN_PASSWORD_RESET', 'admin', (string)$adminId, []);
        return true;
    }

    /** 删除会计管理员账号（不可删开发者 super） */
    public static function deleteAdmin(PDO $pdo, int $adminId, ?int $actorId): bool
    {
        $row = self::findById($pdo, $adminId);
        if (!$row) {
            return false;
        }
        if ((string)$row['role'] === self::ROLE_SUPER) {
            throw new InvalidArgumentException('不能删除开发者账号');
        }
        if ($actorId !== null && $actorId === $adminId) {
            throw new InvalidArgumentException('不能删除当前登录账号');
        }
        $pdo->prepare('DELETE FROM admins WHERE id=?')->execute([$adminId]);
        AppControlService::audit($pdo, $actorId, 'ADMIN_DELETE', 'admin', (string)$adminId, [
            'username' => (string)$row['username'],
        ]);
        return true;
    }
}
