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
        return $row ?: null;
    }

    public static function createToken(array $user, array $cfg): string
    {
        $now = time();
        return Jwt::encode([
            'sub' => (string)$user['id'],
            'username' => $user['username'],
            'iat' => $now,
            'exp' => $now + (int)$cfg['jwt_expire_sec'],
        ], $cfg['jwt_secret']);
    }

    public static function register(PDO $pdo, array $cfg, string $username, string $password, string $licensePlate): array
    {
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
        try {
            $stmt = $pdo->prepare(
                'INSERT INTO users (username, password_hash, license_plate, created_at) VALUES (?, ?, ?, ?)'
            );
            $stmt->execute([$u, $hash, $plate, $now]);
            $userId = (int)$pdo->lastInsertId();
            $pdo->prepare(
                'INSERT INTO ledgers (user_id, data_json, updated_at) VALUES (?, ?, ?)'
            )->execute([$userId, json_encode(['rounds' => []], JSON_UNESCAPED_UNICODE), 0]);
        } catch (PDOException $e) {
            if (strpos($e->getMessage(), 'UNIQUE') !== false) {
                JsonResponse::error('用户名已存在', 409);
            }
            throw $e;
        }
        $user = ['id' => $userId, 'username' => $u, 'license_plate' => $plate];
        return [
            'token' => self::createToken($user, $cfg),
            'username' => $u,
            'user_id' => $userId,
            'license_plate' => $plate,
        ];
    }

    public static function login(PDO $pdo, array $cfg, string $username, string $password): array
    {
        $stmt = $pdo->prepare('SELECT * FROM users WHERE username = ?');
        $stmt->execute([trim($username)]);
        $row = $stmt->fetch();
        if (!$row || !password_verify($password, $row['password_hash'])) {
            JsonResponse::error('用户名或密码错误', 401);
        }
        return [
            'token' => self::createToken($row, $cfg),
            'username' => $row['username'],
            'user_id' => (int)$row['id'],
            'license_plate' => (string)($row['license_plate'] ?? ''),
        ];
    }

    public static function requireUser(PDO $pdo, array $cfg): array
    {
        $user = self::bearerUser($pdo, $cfg);
        if ($user === null) {
            JsonResponse::error('未登录', 401);
        }
        return $user;
    }
}
