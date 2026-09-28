<?php
declare(strict_types=1);

final class AuthService
{
    public static function validateUsername(string $username): ?string
    {
        $u = trim($username);
        if (!preg_match('/^[A-Za-z0-9_]{3,32}$/', $u)) {
            return null;
        }
        return $u;
    }

    public static function validateLicensePlate(string $plate): ?string
    {
        $p = strtoupper(trim($plate));
        $p = str_replace([' ', '·', '.'], '', $p);
        $len = mb_strlen($p, 'UTF-8');
        if ($len < 5 || $len > 10) {
            return null;
        }
        if (!preg_match('/^[\x{4e00}-\x{9fa5}A-Z0-9]+$/u', $p)) {
            return null;
        }
        if (!preg_match('/^[\x{4e00}-\x{9fa5}]/u', $p)) {
            return null;
        }
        return $p;
    }

    public static function isEnabled(array $user): bool
    {
        return EntitlementService::normalizeStatus($user) !== 'SUSPENDED'
            && EntitlementService::normalizeStatus($user) !== 'REVOKED';
    }

    public static function bearerUser(PDO $pdo, array $cfg): ?array
    {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (!preg_match('/^Bearer\s+(\S+)$/i', $header, $m)) {
            return null;
        }
        $payload = Jwt::decode($m[1], $cfg['jwt_secret']);
        if ($payload === null || !isset($payload['sub'])) {
            return null;
        }
        $stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?');
        $stmt->execute([(int)$payload['sub']]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $tokenVer = (int)($payload['ver'] ?? 0);
        $dbVer = (int)($row['token_version'] ?? 0);
        if ($tokenVer !== $dbVer) {
            return null;
        }
        return $row;
    }

    public static function createToken(array $user, array $cfg): string
    {
        $now = time();
        return Jwt::encode([
            'sub' => (string)$user['id'],
            'username' => $user['username'],
            'ver' => (int)($user['token_version'] ?? 0),
            'iat' => $now,
            'exp' => $now + (int)$cfg['jwt_expire_sec'],
        ], $cfg['jwt_secret']);
    }

    public static function publicConfig(PDO $pdo): array
    {
        return [
            'registration_enabled' => SettingsService::isRegistrationEnabled($pdo),
            'trial_days' => SettingsService::trialDays($pdo),
            'latest_version' => SettingsService::get($pdo, 'latest_version', '1.0.0'),
            'announcement' => SettingsService::announcement($pdo),
            'feature_flags' => SettingsService::featureFlags($pdo),
        ];
    }

    public static function register(
        PDO $pdo,
        array $cfg,
        string $username,
        string $password,
        string $licensePlate
    ): array {
        if (!SettingsService::isRegistrationEnabled($pdo)) {
            JsonResponse::error('当前未开放注册，请联系管理员', 403);
        }
        $u = self::validateUsername($username);
        if ($u === null) {
            JsonResponse::error('用户名须为 3–32 位字母、数字或下划线', 400);
        }
        if (strlen($password) < 6) {
            JsonResponse::error('密码至少 6 位', 400);
        }
        $plate = self::validateLicensePlate($licensePlate);
        if ($plate === null) {
            JsonResponse::error('请填写有效车牌号（5–10 位，含省份汉字，如 京A12345）', 400);
        }
        $hash = password_hash($password, PASSWORD_BCRYPT);
        $now = (int)(microtime(true) * 1000);
        $trialDays = SettingsService::trialDays($pdo);
        $plan = 'trial';
        $status = 'ACTIVE';
        $expires = $trialDays > 0 ? $now + ($trialDays * 86400000) : null;
        try {
            $stmt = $pdo->prepare(
                'INSERT INTO users (username, password_hash, license_plate, is_enabled, status, plan, expires_at, token_version, created_at)
                 VALUES (?, ?, ?, 1, ?, ?, ?, 0, ?)'
            );
            $stmt->execute([$u, $hash, $plate, $status, $plan, $expires, $now]);
            $userId = (int)$pdo->lastInsertId();
            $pdo->prepare(
                'INSERT INTO ledgers (user_id, data_json, updated_at, revision) VALUES (?, ?, ?, 0)'
            )->execute([$userId, json_encode(['rounds' => []], JSON_UNESCAPED_UNICODE), 0]);
        } catch (PDOException $e) {
            if (strpos($e->getMessage(), 'UNIQUE') !== false) {
                JsonResponse::error('用户名已存在', 409);
            }
            throw $e;
        }
        $user = [
            'id' => $userId,
            'username' => $u,
            'license_plate' => $plate,
            'is_enabled' => 1,
            'status' => $status,
            'plan' => $plan,
            'expires_at' => $expires,
            'token_version' => 0,
        ];
        $profile = EntitlementService::publicProfile($pdo, $user);
        return array_merge($profile, [
            'token' => self::createToken($user, $cfg),
        ]);
    }

    public static function login(PDO $pdo, array $cfg, string $username, string $password): array
    {
        $stmt = $pdo->prepare('SELECT * FROM users WHERE username = ?');
        $stmt->execute([trim($username)]);
        $row = $stmt->fetch();
        if (!$row || !password_verify($password, $row['password_hash'])) {
            JsonResponse::error('用户名或密码错误', 401);
        }
        EntitlementService::assertLoginAllowed($pdo, $row);
        $profile = EntitlementService::publicProfile($pdo, $row);
        return array_merge($profile, [
            'token' => self::createToken($row, $cfg),
        ]);
    }

    public static function requireUser(PDO $pdo, array $cfg): array
    {
        $user = self::bearerUser($pdo, $cfg);
        if ($user === null) {
            JsonResponse::error('未登录', 401);
        }
        EntitlementService::assertLoginAllowed($pdo, $user);
        return $user;
    }

    public static function changePassword(
        PDO $pdo,
        array $user,
        string $oldPassword,
        string $newPassword
    ): void {
        if (strlen($newPassword) < 6) {
            JsonResponse::error('新密码至少 6 位', 400);
        }
        if (!password_verify($oldPassword, $user['password_hash'])) {
            JsonResponse::error('原密码不正确', 400);
        }
        $hash = password_hash($newPassword, PASSWORD_BCRYPT);
        $pdo->prepare(
            'UPDATE users SET password_hash=?, token_version=token_version+1 WHERE id=?'
        )->execute([$hash, (int)$user['id']]);
    }

    /** 用户自助更新资料（当前仅车牌）。 */
    public static function updateProfile(PDO $pdo, array $user, string $licensePlate): array
    {
        $plate = self::validateLicensePlate($licensePlate);
        if ($plate === null) {
            JsonResponse::error('请填写有效车牌号（5–10 位，含省份汉字，如 京A12345）', 400);
        }
        $pdo->prepare('UPDATE users SET license_plate=? WHERE id=?')
            ->execute([$plate, (int)$user['id']]);
        $user['license_plate'] = $plate;
        return EntitlementService::publicProfile($pdo, $user);
    }

    public static function adminResetPassword(PDO $pdo, int $userId, string $newPassword): ?string
    {
        if (strlen($newPassword) < 6) {
            return null;
        }
        $stmt = $pdo->prepare('SELECT username FROM users WHERE id=?');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $hash = password_hash($newPassword, PASSWORD_BCRYPT);
        $pdo->prepare(
            'UPDATE users SET password_hash=?, token_version=token_version+1 WHERE id=?'
        )->execute([$hash, $userId]);
        AppControlService::audit($pdo, null, 'USER_PASSWORD_RESET', 'user', (string)$userId, [
            'username' => $row['username'],
        ]);
        return (string)$row['username'];
    }
}