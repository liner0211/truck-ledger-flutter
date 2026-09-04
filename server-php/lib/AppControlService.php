<?php
declare(strict_types=1);

final class AppControlService
{
    public static function settings(PDO $pdo): array
    {
        $out = [];
        foreach ($pdo->query('SELECT key, value FROM app_settings') as $row) {
            $out[$row['key']] = $row['value'];
        }
        return $out;
    }

    public static function check(PDO $pdo, array $user, string $appVersion, ?string $deviceId): array
    {
        $s = self::settings($pdo);
        $now = (int)(microtime(true) * 1000);
        $accountStatus = EntitlementService::normalizeStatus($user);
        $device = self::touchDevice($pdo, (int)$user['id'], $deviceId, $appVersion);
        $appStatus = strtoupper((string)($s['app_status'] ?? 'ACTIVE'));
        $minVersion = (string)($s['min_version'] ?? '1.0.0');
        $updateRequired = self::versionCompare($appVersion, $minVersion) < 0
            || (($s['force_update'] ?? '0') === '1');
        $deviceOk = $device === null || ($device['status'] ?? 'ACTIVE') === 'ACTIVE';
        $accountOk = in_array($accountStatus, ['ACTIVE', 'EXPIRED'], true);
        // EXPIRED 仍允许进入（只读由 Entitlement 控制）；SUSPENDED/REVOKED 不允许
        if (in_array($accountStatus, ['SUSPENDED', 'REVOKED'], true)) {
            $accountOk = false;
        }
        if ($accountStatus === 'EXPIRED' && SettingsService::expiryPolicy($pdo) === 'block') {
            $accountOk = false;
        }
        $allowed = $appStatus === 'ACTIVE' && $accountOk && $deviceOk && !$updateRequired;
        $reason = null;
        if ($appStatus !== 'ACTIVE') {
            $reason = $appStatus;
        } elseif (!$accountOk) {
            $reason = $accountStatus;
        } elseif (!$deviceOk) {
            $reason = 'DEVICE_REVOKED';
        } elseif ($updateRequired) {
            $reason = 'UPDATE_REQUIRED';
        }
        return [
            'allowed' => $allowed,
            'reason' => $reason,
            'server_time' => gmdate('c'),
            'app' => [
                'status' => $appStatus,
                'min_version' => $minVersion,
                'latest_version' => (string)($s['latest_version'] ?? '1.0.0'),
                'force_update' => ($s['force_update'] ?? '0') === '1',
                'maintenance_message' => (string)($s['maintenance_message'] ?? ''),
                'control_version' => (int)($s['control_version'] ?? 1),
                'announcement' => (string)($s['announcement'] ?? ''),
            ],
            'account' => EntitlementService::publicProfile($pdo, $user),
            'device' => $device ? ['id' => $device['device_id'], 'status' => $device['status']] : null,
            'policy' => [
                'offline_grace_sec' => max(0, (int)($s['offline_grace_sec'] ?? 259200)),
            ],
            'feature_flags' => SettingsService::featureFlags($pdo),
        ];
    }

    public static function touchDevice(PDO $pdo, int $userId, ?string $deviceId, string $appVersion): ?array
    {
        if ($deviceId === null || trim($deviceId) === '') {
            return null;
        }
        $deviceId = trim($deviceId);
        if (strlen($deviceId) > 128 || !preg_match('/^[A-Za-z0-9._:-]+$/', $deviceId)) {
            JsonResponse::error('设备标识无效', 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM devices WHERE user_id=? AND device_id=?');
        $stmt->execute([$userId, $deviceId]);
        $row = $stmt->fetch();
        $now = (int)(microtime(true) * 1000);
        $platform = strtolower((string)($_SERVER['HTTP_X_APP_PLATFORM'] ?? 'unknown'));
        if (!$row) {
            $pdo->prepare(
                'INSERT INTO devices (user_id, device_id, platform, app_version, status, registered_at, last_seen_at)
                 VALUES (?,?,?,?,?,?,?)'
            )->execute([$userId, $deviceId, $platform, $appVersion, 'ACTIVE', $now, $now]);
            return ['device_id' => $deviceId, 'status' => 'ACTIVE'];
        }
        $pdo->prepare('UPDATE devices SET app_version=?, platform=?, last_seen_at=? WHERE id=?')
            ->execute([$appVersion, $platform, $now, $row['id']]);
        return [
            'device_id' => $row['device_id'],
            'status' => $row['status'],
        ];
    }

    public static function setSetting(PDO $pdo, string $key, string $value, ?int $adminId = null): void
    {
        $allowed = [
            'app_status', 'min_version', 'latest_version', 'force_update',
            'maintenance_message', 'offline_grace_sec', 'announcement',
            'trial_days', 'trial_max_rounds', 'trial_max_attachments', 'expiry_policy',
            'registration_enabled', 'feature_flags',
        ];
        if (!in_array($key, $allowed, true)) {
            JsonResponse::error('不允许修改该配置', 400);
        }
        if ($key === 'app_status' && !in_array($value, ['ACTIVE', 'MAINTENANCE', 'DISABLED'], true)) {
            JsonResponse::error('应用状态无效', 400);
        }
        if ($key === 'force_update' && !in_array($value, ['0', '1'], true)) {
            JsonResponse::error('强制升级值无效', 400);
        }
        if ($key === 'offline_grace_sec' && (!ctype_digit($value) || (int)$value > 31536000)) {
            JsonResponse::error('离线宽限时间无效', 400);
        }
        if ($key === 'expiry_policy' && !in_array($value, ['readonly', 'block'], true)) {
            JsonResponse::error('到期策略无效', 400);
        }
        $old = self::settings($pdo)[$key] ?? null;
        SettingsService::set($pdo, $key, $value);
        $now = (int)(microtime(true) * 1000);
        $pdo->prepare(
            "UPDATE app_settings SET value = CAST(CAST(value AS INTEGER)+1 AS TEXT), updated_at=? WHERE key='control_version'"
        )->execute([$now]);
        self::audit($pdo, $adminId, 'APP_SETTING_UPDATE', 'app_settings', $key, [
            'before' => $old,
            'after' => $value,
        ]);
    }

    public static function setUserEntitlement(
        PDO $pdo,
        int $userId,
        string $status,
        string $plan,
        ?int $expiresAt,
        bool $bumpToken,
        ?int $adminId
    ): bool {
        if (!in_array($status, ['ACTIVE', 'SUSPENDED', 'REVOKED', 'EXPIRED'], true)) {
            JsonResponse::error('用户状态无效', 400);
        }
        if (!in_array($plan, ['trial', 'paid'], true)) {
            JsonResponse::error('套餐无效', 400);
        }
        $stmt = $pdo->prepare('SELECT username, status, plan, expires_at FROM users WHERE id=?');
        $stmt->execute([$userId]);
        $u = $stmt->fetch();
        if (!$u) {
            return false;
        }
        $enabled = in_array($status, ['ACTIVE', 'EXPIRED'], true) ? 1 : 0;
        if ($bumpToken) {
            $pdo->prepare(
                'UPDATE users SET status=?, plan=?, expires_at=?, is_enabled=?, token_version=token_version+1 WHERE id=?'
            )->execute([$status, $plan, $expiresAt, $enabled, $userId]);
        } else {
            $pdo->prepare(
                'UPDATE users SET status=?, plan=?, expires_at=?, is_enabled=? WHERE id=?'
            )->execute([$status, $plan, $expiresAt, $enabled, $userId]);
        }
        self::audit($pdo, $adminId, 'USER_ENTITLEMENT_UPDATE', 'user', (string)$userId, [
            'before' => $u,
            'after' => ['status' => $status, 'plan' => $plan, 'expires_at' => $expiresAt],
        ]);
        return true;
    }

    public static function setDeviceStatus(PDO $pdo, int $userId, string $deviceId, string $status, ?int $adminId): bool
    {
        if (!in_array($status, ['ACTIVE', 'REVOKED'], true)) {
            JsonResponse::error('设备状态无效', 400);
        }
        $stmt = $pdo->prepare('SELECT id, status FROM devices WHERE user_id=? AND device_id=?');
        $stmt->execute([$userId, $deviceId]);
        $row = $stmt->fetch();
        if (!$row) {
            return false;
        }
        $pdo->prepare('UPDATE devices SET status=? WHERE id=?')->execute([$status, $row['id']]);
        self::audit($pdo, $adminId, 'DEVICE_STATUS_UPDATE', 'device', $deviceId, [
            'user_id' => $userId,
            'before' => $row['status'],
            'after' => $status,
        ]);
        return true;
    }

    public static function listDevices(PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare(
            'SELECT device_id, platform, app_version, status, registered_at, last_seen_at
             FROM devices WHERE user_id=? ORDER BY last_seen_at DESC'
        );
        $stmt->execute([$userId]);
        $out = [];
        foreach ($stmt as $row) {
            $out[] = [
                'device_id' => $row['device_id'],
                'platform' => $row['platform'],
                'app_version' => $row['app_version'],
                'status' => $row['status'],
                'registered_at' => (int)$row['registered_at'],
                'last_seen_at' => (int)$row['last_seen_at'],
            ];
        }
        return $out;
    }

    public static function audit(
        PDO $pdo,
        ?int $adminId,
        string $action,
        string $targetType,
        string $targetId,
        array $details
    ): void {
        $pdo->prepare(
            'INSERT INTO audit_logs (admin_id, action, target_type, target_id, details_json, created_at)
             VALUES (?,?,?,?,?,?)'
        )->execute([
            $adminId,
            $action,
            $targetType,
            $targetId,
            json_encode($details, JSON_UNESCAPED_UNICODE),
            (int)(microtime(true) * 1000),
        ]);
    }

    public static function recentAudits(PDO $pdo, int $limit = 50): array
    {
        $limit = max(1, min(200, $limit));
        $stmt = $pdo->query(
            "SELECT id, action, target_type, target_id, details_json, created_at
             FROM audit_logs ORDER BY id DESC LIMIT {$limit}"
        );
        $out = [];
        foreach ($stmt as $row) {
            $out[] = [
                'id' => (int)$row['id'],
                'action' => $row['action'],
                'target_type' => $row['target_type'],
                'target_id' => $row['target_id'],
                'details' => json_decode((string)$row['details_json'], true),
                'created_at' => (int)$row['created_at'],
            ];
        }
        return $out;
    }

    private static function versionCompare(string $a, string $b): int
    {
        $pa = array_map('intval', preg_split('/[^0-9]+/', $a) ?: [0]);
        $pb = array_map('intval', preg_split('/[^0-9]+/', $b) ?: [0]);
        for ($i = 0; $i < 3; $i++) {
            $x = $pa[$i] ?? 0;
            $y = $pb[$i] ?? 0;
            if ($x !== $y) {
                return $x <=> $y;
            }
        }
        return 0;
    }
}
